#if os(macOS)
import Foundation
import ImageIO
import MetalKit

enum RemoteTextureProcessing: Hashable {
    case raw
    case cloudDensity
}

private struct RemoteTextureKey: Hashable {
    let urlString: String
    let isSRGB: Bool
    let processing: RemoteTextureProcessing
}

private final class RemoteTextureEntry {
    var texture: MTLTexture?
    var lastRequestTime: CFTimeInterval = -.greatestFiniteMagnitude
    var isLoading = false
}

final class RendererTextureStore {
    private static let maxRemoteTextureBytes = 64 * 1024 * 1024
    private static let maxRemoteTextureDimension = 16_384
    private static let maxRemoteTexturePixels = 8192 * 8192
    private static let remoteTextureSession: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 20
        configuration.timeoutIntervalForResource = 45
        configuration.httpMaximumConnectionsPerHost = 2
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        return URLSession(configuration: configuration)
    }()

    private let device: MTLDevice
    private let commandQueue: MTLCommandQueue
    private let textureLoader: MTKTextureLoader
    private let fallbackTexture: MTLTexture
    private let reportIssue: (String) -> Void

    private var textureCache: [String: MTLTexture] = [:]
    private var dataTextureCache: [String: MTLTexture] = [:]
    private var remoteTextureCache: [RemoteTextureKey: RemoteTextureEntry] = [:]
    private let remoteTextureLock = NSLock()

    init(
        device: MTLDevice,
        commandQueue: MTLCommandQueue,
        fallbackTexture: MTLTexture,
        reportIssue: @escaping (String) -> Void
    ) {
        self.device = device
        self.commandQueue = commandQueue
        self.textureLoader = MTKTextureLoader(device: device)
        self.fallbackTexture = fallbackTexture
        self.reportIssue = reportIssue
    }

    func texture(named name: String) -> MTLTexture {
        if let cached = textureCache[name] {
            return cached
        }

        guard let url = Bundle.main.textureURL(named: name) else {
            reportIssue("Missing texture resource: \(name)")
            return fallbackTexture
        }

        do {
            let texture = try textureLoader.newTexture(URL: url, options: [
                MTKTextureLoader.Option.SRGB: true,
                MTKTextureLoader.Option.generateMipmaps: true,
            ])
            textureCache[name] = texture
            return texture
        } catch {
            reportIssue("Failed to load texture '\(name)': \(error.localizedDescription)")
            return fallbackTexture
        }
    }

    func dataTexture(named name: String) -> MTLTexture {
        if let cached = dataTextureCache[name] {
            return cached
        }

        guard let url = Bundle.main.textureURL(named: name) else {
            reportIssue("Missing data texture resource: \(name)")
            return fallbackTexture
        }

        do {
            let texture = try textureLoader.newTexture(URL: url, options: [
                MTKTextureLoader.Option.SRGB: false,
                MTKTextureLoader.Option.generateMipmaps: true,
            ])
            dataTextureCache[name] = texture
            return texture
        } catch {
            if let texture = makeGrayscaleDataTexture(from: url) {
                dataTextureCache[name] = texture
                return texture
            }
            reportIssue("Failed to load data texture '\(name)': \(error.localizedDescription)")
            return fallbackTexture
        }
    }

    func remoteTexture(
        urlString: String,
        isSRGB: Bool,
        processing: RemoteTextureProcessing = .raw,
        refreshInterval: TimeInterval,
        at timestamp: CFTimeInterval
    ) -> MTLTexture? {
        let key = RemoteTextureKey(urlString: urlString, isSRGB: isSRGB, processing: processing)
        let minimumInterval = max(refreshInterval, 5)

        remoteTextureLock.lock()
        let entry: RemoteTextureEntry
        if let cachedEntry = remoteTextureCache[key] {
            entry = cachedEntry
        } else {
            let newEntry = RemoteTextureEntry()
            remoteTextureCache[key] = newEntry
            entry = newEntry
        }

        let cachedTexture = entry.texture
        let shouldRefresh = !entry.isLoading && timestamp - entry.lastRequestTime >= minimumInterval
        if shouldRefresh {
            entry.isLoading = true
            entry.lastRequestTime = timestamp
        }
        remoteTextureLock.unlock()

        if shouldRefresh {
            refreshRemoteTexture(key: key)
        }

        return cachedTexture
    }

    private func refreshRemoteTexture(key: RemoteTextureKey) {
        guard let url = URL(string: key.urlString) else {
            reportIssue("Invalid remote texture URL: \(key.urlString)")
            finishRemoteTextureLoad(key: key, texture: nil)
            return
        }
        guard let scheme = url.scheme?.lowercased(),
              scheme == "https" || scheme == "http" else {
            reportIssue("Unsupported remote texture URL scheme: \(key.urlString)")
            finishRemoteTextureLoad(key: key, texture: nil)
            return
        }

        Self.remoteTextureSession.dataTask(with: url) { [weak self] data, response, error in
            guard let self else { return }
            if let error {
                self.reportIssue("Remote texture request failed for \(url.host ?? key.urlString): \(error.localizedDescription)")
                self.finishRemoteTextureLoad(key: key, texture: nil)
                return
            }
            guard let httpResponse = response as? HTTPURLResponse else {
                self.reportIssue("Remote texture response was not HTTP: \(key.urlString)")
                self.finishRemoteTextureLoad(key: key, texture: nil)
                return
            }
            guard (200..<300).contains(httpResponse.statusCode) else {
                self.reportIssue("Remote texture request returned HTTP \(httpResponse.statusCode): \(key.urlString)")
                self.finishRemoteTextureLoad(key: key, texture: nil)
                return
            }
            guard let data,
                  self.validateRemoteTexture(data: data, response: httpResponse, key: key) else {
                self.finishRemoteTextureLoad(key: key, texture: nil)
                return
            }

            let texture: MTLTexture?
            switch key.processing {
            case .cloudDensity:
                texture = self.makeCloudDensityTexture(from: data)
            case .raw:
                texture = try? self.textureLoader.newTexture(data: data, options: [
                    MTKTextureLoader.Option.SRGB: key.isSRGB,
                    MTKTextureLoader.Option.generateMipmaps: true,
                ])
            }

            if texture == nil {
                self.reportIssue("Failed to decode remote texture: \(key.urlString)")
            }
            self.finishRemoteTextureLoad(key: key, texture: texture)
        }.resume()
    }

    private func validateRemoteTexture(
        data: Data,
        response: HTTPURLResponse,
        key: RemoteTextureKey
    ) -> Bool {
        if response.expectedContentLength > Int64(Self.maxRemoteTextureBytes) {
            reportIssue("Remote texture is too large: \(key.urlString)")
            return false
        }
        guard data.count <= Self.maxRemoteTextureBytes else {
            reportIssue("Remote texture exceeded \(Self.maxRemoteTextureBytes / (1024 * 1024)) MB: \(key.urlString)")
            return false
        }

        if let mimeType = response.mimeType?.lowercased(),
           !mimeType.hasPrefix("image/") {
            reportIssue("Remote texture is not an image (\(mimeType)): \(key.urlString)")
            return false
        }

        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? Int,
              let height = properties[kCGImagePropertyPixelHeight] as? Int else {
            reportIssue("Remote texture image metadata could not be read: \(key.urlString)")
            return false
        }

        guard width > 0, height > 0,
              width <= Self.maxRemoteTextureDimension,
              height <= Self.maxRemoteTextureDimension,
              width * height <= Self.maxRemoteTexturePixels else {
            reportIssue("Remote texture dimensions are unsupported (\(width)x\(height)): \(key.urlString)")
            return false
        }

        return true
    }

    private func makeCloudDensityTexture(from data: Data) -> MTLTexture? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let cgImage = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
            return nil
        }

        let width = cgImage.width
        let height = cgImage.height
        guard width > 0, height > 0 else { return nil }

        let pixelCount = width * height
        let bytesPerRow = width * 4
        var rgba = [UInt8](repeating: 0, count: pixelCount * 4)
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let context = CGContext(
            data: &rgba,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            return nil
        }
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))

        var alphaMin: UInt8 = 255
        var alphaMax: UInt8 = 0
        var sampleIndex = 3
        let sampleStride = max(1, pixelCount / 100_000) * 4
        while sampleIndex < rgba.count {
            let alpha = rgba[sampleIndex]
            if alpha < alphaMin { alphaMin = alpha }
            if alpha > alphaMax { alphaMax = alpha }
            sampleIndex += sampleStride
        }
        let alphaCarriesMask = Int(alphaMax) - Int(alphaMin) > 8

        var density = [UInt8](repeating: 0, count: pixelCount)
        for pixelIndex in 0..<pixelCount {
            let rgbaOffset = pixelIndex * 4
            if alphaCarriesMask {
                density[pixelIndex] = rgba[rgbaOffset + 3]
            } else {
                let red = Int(rgba[rgbaOffset])
                let green = Int(rgba[rgbaOffset + 1])
                let blue = Int(rgba[rgbaOffset + 2])
                density[pixelIndex] = UInt8((red * 299 + green * 587 + blue * 114) / 1000)
            }
        }

        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .r8Unorm,
            width: width,
            height: height,
            mipmapped: true
        )
        descriptor.usage = [.shaderRead]
        guard let texture = device.makeTexture(descriptor: descriptor) else { return nil }
        texture.replace(
            region: MTLRegionMake2D(0, 0, width, height),
            mipmapLevel: 0,
            withBytes: density,
            bytesPerRow: width
        )
        generateMipmaps(for: texture)
        return texture
    }

    private func makeGrayscaleDataTexture(from url: URL) -> MTLTexture? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let cgImage = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
            return nil
        }

        let width = cgImage.width
        let height = cgImage.height
        guard width > 0, height > 0 else { return nil }

        let pixelCount = width * height
        let bytesPerRow = width * 4
        var rgba = [UInt8](repeating: 0, count: pixelCount * 4)
        guard let context = CGContext(
            data: &rgba,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            return nil
        }
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))

        var grayscale = [UInt8](repeating: 0, count: pixelCount)
        for pixelIndex in 0..<pixelCount {
            let rgbaOffset = pixelIndex * 4
            let red = Int(rgba[rgbaOffset])
            let green = Int(rgba[rgbaOffset + 1])
            let blue = Int(rgba[rgbaOffset + 2])
            grayscale[pixelIndex] = UInt8((red * 299 + green * 587 + blue * 114) / 1000)
        }

        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .r8Unorm,
            width: width,
            height: height,
            mipmapped: true
        )
        descriptor.usage = [.shaderRead]
        guard let texture = device.makeTexture(descriptor: descriptor) else {
            return nil
        }
        texture.replace(
            region: MTLRegionMake2D(0, 0, width, height),
            mipmapLevel: 0,
            withBytes: grayscale,
            bytesPerRow: width
        )
        generateMipmaps(for: texture)
        return texture
    }

    private func generateMipmaps(for texture: MTLTexture) {
        guard texture.mipmapLevelCount > 1,
              let commandBuffer = commandQueue.makeCommandBuffer(),
              let blit = commandBuffer.makeBlitCommandEncoder() else {
            return
        }
        blit.generateMipmaps(for: texture)
        blit.endEncoding()
        commandBuffer.commit()
        commandBuffer.waitUntilCompleted()
    }

    private func finishRemoteTextureLoad(key: RemoteTextureKey, texture: MTLTexture?) {
        remoteTextureLock.lock()
        defer { remoteTextureLock.unlock() }

        let entry = remoteTextureCache[key] ?? RemoteTextureEntry()
        if remoteTextureCache[key] == nil {
            remoteTextureCache[key] = entry
        }
        if let texture {
            entry.texture = texture
        }
        entry.isLoading = false
    }
}
#endif
