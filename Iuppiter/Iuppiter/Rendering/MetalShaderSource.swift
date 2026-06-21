#if os(macOS)
enum MetalShaderSource {
    static let planet = #"""
    #include <metal_stdlib>
    using namespace metal;

    struct VertexIn {
        float3 position [[attribute(0)]];
        float3 normal   [[attribute(1)]];
        float2 uv       [[attribute(2)]];
    };

    // ── Uniforms ──────────────────────────────────────────────────────────────
    // NOTE: specularRoughness occupies the slot that was previously elapsedTime.
    // It is unused by the vertex shader and drives Oren-Nayar + Blinn-Phong in the
    // fragment shader. starCameraDistance controls the star close-up brightness boost.
    struct RenderUniforms {
        float4x4 modelMatrix;
        float4x4 viewProjectionMatrix;
        float4x4 normalMatrix;
        float4   sunDirection;
        float4   tintColor;
        float4   cameraPosition;      // xyz = camera world position (focus-relative)
        float    opacity;
        float    layerKind;
        float    specularRoughness;   // [0=mirror … 1=fully diffuse]; star draws: unused
        float    starCameraDistance;  // star draws: camera-to-star distance
        float    bumpStrength;
        float    specularMapStrength;
        float    hasBumpMap;
        float    hasSpecularMap;
        float    textureProjection;
        float    bumpMapIsNormalMap;
        float    emissionMapStrength;
        float    hasEmissionMap;
        float    surfaceTintStrength;
    };

    struct OrbitVertex  { float3 position; float4 color; };
    struct OrbitUniforms { float4x4 viewProjectionMatrix; };

    struct LightingOccluder  { float4 positionRadius; };
    struct LightingParameters {
        float4 sunPositionRadius;
        int    occluderCount;
        int    selfOccluderIndex;
        float2 padding;
    };

    // Describes the equatorial ring plane of a ringed planet for shadow projection.
    struct RingShadow {
        float4 planeNormal;   // xyz = world-space ring-plane normal; w = 1 if present
        float4 planetCenter;  // xyz = planet centre (focus-relative); w = inner radius
        float  outerRadius;   // outer radius in the same world units
        float  pad0, pad1, pad2;
    };

    struct VertexOut {
        float4 position [[position]];
        float3 worldNormal;
        float3 worldPosition;
        float3 localPosition;
        float3 localNormal;
        float2 uv;
    };

    struct OrbitVertexOut {
        float4 position [[position]];
        float4 color;
    };

    struct FlareVertex {
        float2 position;
        float2 local;
        float4 color;
    };

    struct FlareVertexOut {
        float4 position [[position]];
        float4 color;
        float2 local;
    };

    // ── Vertex shader ─────────────────────────────────────────────────────────
    vertex VertexOut planetVertex(VertexIn in [[stage_in]],
                                  constant RenderUniforms& uniforms [[buffer(1)]]) {
        float4 worldPos = uniforms.modelMatrix * float4(in.position, 1.0);
        VertexOut out;
        out.position    = uniforms.viewProjectionMatrix * worldPos;
        out.worldPosition = worldPos.xyz;
        out.worldNormal = normalize((uniforms.normalMatrix * float4(in.normal, 0.0)).xyz);
        out.localPosition = in.position;
        out.localNormal = in.normal;
        out.uv = in.uv;
        return out;
    }

    // ── Shadow helpers ────────────────────────────────────────────────────────
    float circleOverlap(float r1, float r2, float d) {
        if (r1 <= 0.0 || r2 <= 0.0 || d >= r1 + r2) return 0.0;
        if (d <= abs(r1 - r2)) { float r = min(r1, r2); return 3.141592653589793 * r * r; }
        float d2 = d*d, r12 = r1*r1, r22 = r2*r2;
        float a = r12 * acos(clamp((d2+r12-r22)/(2.0*d*r1), -1.0, 1.0));
        float b = r22 * acos(clamp((d2+r22-r12)/(2.0*d*r2), -1.0, 1.0));
        float c = 0.5 * sqrt(max(0.0, (-d+r1+r2)*(d+r1-r2)*(d-r1+r2)*(d+r1+r2)));
        return a + b - c;
    }

    // Analytic angular-disk eclipse: returns fraction of sunlight reaching 'point'.
    float sphereSunVisibility(float3 point,
                              constant LightingOccluder* occluders,
                              constant LightingParameters& lighting) {
        float3 toSun      = lighting.sunPositionRadius.xyz - point;
        float  sunDist    = length(toSun);
        float  sunRadius  = lighting.sunPositionRadius.w;
        if (sunDist <= max(sunRadius, 1e-6)) return 1.0;

        float3 sunDir          = toSun / sunDist;
        float  sunAngR         = asin(clamp(sunRadius / sunDist, 0.0, 0.95));
        float  sunArea         = 3.141592653589793 * sunAngR * sunAngR;
        float  visibility      = 1.0;

        for (int i = 0; i < 32; i++) {
            if (i >= lighting.occluderCount) break;
            if (i == lighting.selfOccluderIndex) continue;

            float4 occ     = occluders[i].positionRadius;
            float3 toOcc   = occ.xyz - point;
            float  occR    = occ.w;
            float  occDist = length(toOcc);
            if (occDist <= max(occR, 1e-6)) continue;

            float alongSun = dot(toOcc, sunDir);
            if (alongSun <= 0.0 || alongSun >= sunDist) continue;

            float3 occDir    = toOcc / occDist;
            float  occAngR   = asin(clamp(occR / occDist, 0.0, 0.95));
            float  angSep    = acos(clamp(dot(sunDir, occDir), -1.0, 1.0));
            float overlap = circleOverlap(sunAngR, occAngR, angSep);
            float coverage = clamp(overlap / max(sunArea, 1e-6), 0.0, 1.0);

            // A satellite only produces a fully dark umbra when its apparent disk
            // comfortably exceeds the Sun's apparent disk from this surface point.
            // Near the umbra limit, keep the shadow in penumbra territory instead
            // of snapping to a black disk.
            float angularMargin = occAngR - sunAngR;
            float totality = smoothstep(0.0, max(sunAngR * 0.45, 1e-5), angularMargin);
            float maximumShadow = mix(0.72, 1.0, totality);
            visibility *= 1.0 - coverage * maximumShadow;
        }
        return clamp(visibility, 0.0, 1.0);
    }

    // Ring-plane shadow: traces a ray from 'fragPos' toward the sun, tests whether
    // it hits the ring annulus, and samples the ring texture for shadow density.
    // Returns a shadow multiplier: 1 = full sunlight, 0 = fully occluded.
    float computeRingShadow(float3 fragPos,
                            float3 sunPos,
                            constant RingShadow& ring,
                            texture2d<float> ringTex,
                            sampler samp) {
        if (ring.planeNormal.w < 0.5) return 1.0;

        float3 toSun     = sunPos - fragPos;
        float  toSunDist = length(toSun);
        if (toSunDist < 1e-4) return 1.0;
        float3 sunDir = toSun / toSunDist;

        float3 planeN  = ring.planeNormal.xyz;
        float3 center  = ring.planetCenter.xyz;
        float  innerR  = ring.planetCenter.w;
        float  outerR  = ring.outerRadius;

        float denom = dot(sunDir, planeN);
        if (abs(denom) < 1e-4) return 1.0;

        float t = dot(center - fragPos, planeN) / denom;
        // Use strict-negative cutoff (not 0.001) so near-equatorial surface
        // fragments that are just barely in the shadowed hemisphere are not skipped.
        if (t < 0.0 || t >= toSunDist) return 1.0;

        float3 hit   = fragPos + sunDir * t;
        float3 toHit = hit - center;
        toHit -= dot(toHit, planeN) * planeN;   // project onto ring plane
        float r = length(toHit);

        if (r < innerR || r > outerR) return 1.0;

        float radialUV  = clamp((r - innerR) / max(outerR - innerR, 1e-4), 0.0, 1.0);
        float4 ringTexel = ringTex.sample(samp, float2(radialUV, 0.5));
        // The ring texture has RGB data in transparent padding; only alpha
        // represents physical ring opacity for shadows.
        float  ringAlpha = smoothstep(0.03, 0.85, ringTexel.a);

        // 0.97 factor: nearly-opaque ring bands cast nearly-full shadow.
        return 1.0 - ringAlpha * 0.97;
    }

    // ── Simplified Oren-Nayar diffuse ─────────────────────────────────────────
    // More accurate than Lambert for rough planetary surfaces (Moon, Mercury, Mars).
    // Produces retroreflection at high angles, matching spacecraft photometry.
        float orenNayarDiffuse(float NdotL, float NdotV, float3 normal,
                               float3 sunDir, float3 viewDir, float roughness) {
        float sigma2 = roughness * roughness;
        float A = 1.0 - 0.5 * sigma2 / (sigma2 + 0.33);
        float B = 0.45 * sigma2 / (sigma2 + 0.09);

        float sinNL = sqrt(max(0.0, 1.0 - NdotL * NdotL));
        float sinNV = sqrt(max(0.0, 1.0 - NdotV * NdotV));

        float3 vPerp = viewDir  - normal * NdotV;
        float3 lPerp = sunDir   - normal * NdotL;
        float  lenV  = length(vPerp);
        float  lenL  = length(lPerp);
        float cosPhi = (lenV > 1e-3 && lenL > 1e-3)
            ? max(0.0, dot(vPerp / lenV, lPerp / lenL)) : 0.0;

        float C = sinNL * sinNV / max(max(NdotL, NdotV), 1e-3);
            return NdotL * (A + B * cosPhi * C);
        }

        float mapLuminance(float3 value) {
            return dot(value, float3(0.2126, 0.7152, 0.0722));
        }

        float hash31(float3 p) {
            p = fract(p * 0.1031);
            p += dot(p, p.yzx + 33.33);
            return fract((p.x + p.y) * p.z);
        }

        float valueNoise(float3 p) {
            float3 i = floor(p);
            float3 f = smoothstep(float3(0.0), float3(1.0), fract(p));

            float n000 = hash31(i + float3(0.0, 0.0, 0.0));
            float n100 = hash31(i + float3(1.0, 0.0, 0.0));
            float n010 = hash31(i + float3(0.0, 1.0, 0.0));
            float n110 = hash31(i + float3(1.0, 1.0, 0.0));
            float n001 = hash31(i + float3(0.0, 0.0, 1.0));
            float n101 = hash31(i + float3(1.0, 0.0, 1.0));
            float n011 = hash31(i + float3(0.0, 1.0, 1.0));
            float n111 = hash31(i + float3(1.0, 1.0, 1.0));

            float nx00 = mix(n000, n100, f.x);
            float nx10 = mix(n010, n110, f.x);
            float nx01 = mix(n001, n101, f.x);
            float nx11 = mix(n011, n111, f.x);
            float nxy0 = mix(nx00, nx10, f.y);
            float nxy1 = mix(nx01, nx11, f.y);
            return mix(nxy0, nxy1, f.z);
        }

        float2 sphericalProjectedUV(float3 localPosition, float3 localNormal) {
            float3 direction = length(localPosition) > 1e-4
                ? normalize(localPosition)
                : normalize(localNormal);
            float u = 0.5 - atan2(direction.z, direction.x) / (2.0 * 3.141592653589793);
            float v = acos(clamp(direction.y, -1.0, 1.0)) / 3.141592653589793;
            return float2(fract(u), clamp(v, 0.0, 1.0));
        }

        float3 perturbNormalFromHeight(float3 normal,
                                       float3 worldPosition,
                                       float2 uv,
                                       texture2d<float> bumpTexture,
                                       sampler samp,
                                       float strength) {
            if (strength <= 0.0) return normal;

            float2 texel = 1.0 / float2(
                max(float(bumpTexture.get_width()), 1.0),
                max(float(bumpTexture.get_height()), 1.0)
            );

            float hL = mapLuminance(bumpTexture.sample(samp, uv - float2(texel.x, 0.0)).rgb);
            float hR = mapLuminance(bumpTexture.sample(samp, uv + float2(texel.x, 0.0)).rgb);
            float hD = mapLuminance(bumpTexture.sample(samp, uv - float2(0.0, texel.y)).rgb);
            float hU = mapLuminance(bumpTexture.sample(samp, uv + float2(0.0, texel.y)).rgb);

            float3 dpdx = dfdx(worldPosition);
            float3 dpdy = dfdy(worldPosition);
            float2 duvdx = dfdx(uv);
            float2 duvdy = dfdy(uv);
            float det = duvdx.x * duvdy.y - duvdx.y * duvdy.x;
            if (abs(det) < 1e-5) return normal;

            float3 tangent = dpdx * duvdy.y - dpdy * duvdx.y;
            float3 bitangent = dpdy * duvdx.x - dpdx * duvdy.x;
            if (length(tangent) < 1e-5 || length(bitangent) < 1e-5) return normal;

            tangent = normalize(tangent);
            bitangent = normalize(bitangent);

            float dHdu = (hR - hL) * strength;
            float dHdv = (hU - hD) * strength;
            return normalize(normal - tangent * dHdu - bitangent * dHdv);
        }

        float3 perturbNormalFromNormalMap(float3 normal,
                                          float3 worldPosition,
                                          float2 uv,
                                          texture2d<float> normalTexture,
                                          sampler samp,
                                          float strength) {
            if (strength <= 0.0) return normal;

            float3 dpdx = dfdx(worldPosition);
            float3 dpdy = dfdy(worldPosition);
            float2 duvdx = dfdx(uv);
            float2 duvdy = dfdy(uv);
            float det = duvdx.x * duvdy.y - duvdx.y * duvdy.x;
            if (abs(det) < 1e-5) return normal;

            float3 tangent = dpdx * duvdy.y - dpdy * duvdx.y;
            float3 bitangent = dpdy * duvdx.x - dpdx * duvdy.x;
            if (length(tangent) < 1e-5 || length(bitangent) < 1e-5) return normal;

            tangent = normalize(tangent);
            bitangent = normalize(bitangent);

            float3 tangentNormal = normalTexture.sample(samp, uv).rgb * 2.0 - 1.0;
            tangentNormal.xy *= strength;
            tangentNormal.z = max(tangentNormal.z, 0.001);
            tangentNormal = normalize(tangentNormal);

            return normalize(
                tangent * tangentNormal.x +
                bitangent * tangentNormal.y +
                normal * tangentNormal.z
            );
        }

        // ── Main planet fragment shader ───────────────────────────────────────────
        fragment float4 planetFragment(VertexOut in [[stage_in]],
                                   constant RenderUniforms&  uniforms   [[buffer(1)]],
                                   constant LightingOccluder* occluders  [[buffer(2)]],
                                   constant LightingParameters& lighting  [[buffer(3)]],
                                       constant RingShadow&       ringShadow [[buffer(4)]],
                                       texture2d<float>           surfaceTexture [[texture(0)]],
                                       texture2d<float>           ringTexture    [[texture(1)]],
                                       texture2d<float>           bumpTexture    [[texture(2)]],
                                       texture2d<float>           specularTexture [[texture(3)]],
                                       texture2d<float>           emissionTexture [[texture(4)]],
                                       sampler                    surfaceSampler [[sampler(0)]]) {

        float2 surfaceUV = uniforms.textureProjection > 0.5
            ? sphericalProjectedUV(in.localPosition, in.localNormal)
            : in.uv;
        float4 texel      = surfaceTexture.sample(surfaceSampler, surfaceUV);
        if (uniforms.layerKind > 4.5) {
            float3 sky = pow(max(texel.rgb, float3(0.0)), float3(0.82));
            return float4(sky * 0.78, 1.0);
        }

            float3 normal     = normalize(in.worldNormal);
            if (uniforms.layerKind < 0.5 && uniforms.hasBumpMap > 0.5) {
                if (uniforms.bumpMapIsNormalMap > 0.5) {
                    normal = perturbNormalFromNormalMap(
                        normal,
                        in.worldPosition,
                        surfaceUV,
                        bumpTexture,
                        surfaceSampler,
                        uniforms.bumpStrength
                    );
                } else {
                    normal = perturbNormalFromHeight(
                        normal,
                        in.worldPosition,
                        surfaceUV,
                        bumpTexture,
                        surfaceSampler,
                        uniforms.bumpStrength
                    );
                }
            }
            float3 sunDir     = normalize(uniforms.sunDirection.xyz);
            float  NdotL_raw  = dot(normal, sunDir);
        float  visibility = sphereSunVisibility(in.worldPosition, occluders, lighting);

        // ── Procedural body (small moon, no texture) ─────────────────────────
        if (uniforms.layerKind > 3.5) {
            float diffuse = max(NdotL_raw, 0.0) * visibility * 1.18;
            float3 p = normalize(in.localPosition + in.localNormal * 0.35);
            float broad = valueNoise(p * 4.0);
            float fine = valueNoise(p * 18.0);
            float mottling = mix(0.72, 1.22, broad) * mix(0.88, 1.12, fine);
            float3 dust = mix(uniforms.tintColor.rgb * 0.72, uniforms.tintColor.rgb * 1.18, broad);
            return float4(dust * mottling * diffuse, uniforms.opacity);
        }

        // ── Star / self-luminous body ─────────────────────────────────────────
        // Improvement 1 (from analysis): use actual view direction for limb darkening
        // so the correct limb is shown regardless of camera orientation.
        // Improvement 2: scale brightness with camera proximity for dramatic close-ups.
        if (uniforms.layerKind > 2.5) {
            float3 viewDir  = normalize(uniforms.cameraPosition.xyz - in.worldPosition);
            float  NdotV    = clamp(abs(dot(normal, viewDir)), 0.0, 1.0);
            float  limb     = pow(1.0 - NdotV, 1.8);

            float camDist   = max(uniforms.starCameraDistance, 0.001);
            float proxBoost = 1.0 + 5.0 * exp(-camDist * 0.03);

            float3 base   = texel.rgb * mix(float3(1.35, 1.04, 0.65), uniforms.tintColor.rgb, 0.28);
            float3 corona = float3(0.95, 0.52, 0.10) * limb;
            float3 color  = (base + corona) * proxBoost;
            return float4(clamp(color, 0.0, 3.5), texel.a * uniforms.opacity);
        }

        // ── Cloud layer ───────────────────────────────────────────────────────
        if (uniforms.layerKind > 0.5) {
            // Cloud textures are pre-processed on the CPU into a single linear
            // density channel (see makeCloudDensityTexture): .r is the cloud
            // mask, regardless of whether the source stored it in alpha or
            // luminance. 0 == clear sky, 1 == thick cloud.
            float density = texel.r;

            // Remap so open ocean/clear sky stays transparent and only genuine
            // cloud systems render. The live mask sits high (median ~0.8), so the
            // threshold starts well above clear-sky values.
            float cloudMask = smoothstep(0.62, 0.92, density);
            if (cloudMask < 0.01) {
                discard_fragment();
            }

            // Light clouds like the surface: bright on the day side with a soft
            // terminator that fades out alongside the surface lighting, so there
            // is no hard seam at the limb and no veil on the night side.
            float  dayLight = smoothstep(-0.10, 0.20, NdotL_raw) * visibility;
            float3 color    = float3(mix(0.04, 1.10, dayLight));
            float  alpha    = pow(cloudMask, 0.8) * uniforms.opacity * dayLight;
            return float4(color, min(alpha, 1.0));
        }

        // ── Base solid planet surface ─────────────────────────────────────────
        // Implements all remaining improvements from the analysis:
        //  • Ring shadow on Saturn (request 3)
        //  • Genuinely dark night side (request 1 / improvement 5)
        //  • Oren-Nayar diffuse for rough rocky surfaces (improvement 6)
        //  • Blinn-Phong specular with per-body roughness (improvement 7)
        //  • Specular correctly gated on visibility + ring shadow

        float ringShadowFactor = computeRingShadow(
            in.worldPosition, lighting.sunPositionRadius.xyz,
            ringShadow, ringTexture, surfaceSampler);

        float3 viewDir = normalize(uniforms.cameraPosition.xyz - in.worldPosition);
        float  NdotL   = max(NdotL_raw, 0.0);
        float  NdotV   = max(dot(normal, viewDir), 0.0);

        float roughness = clamp(uniforms.specularRoughness, 0.05, 1.0);

        // Oren-Nayar diffuse (reduces to Lambert when roughness → 0).
        float diffuse = orenNayarDiffuse(NdotL, NdotV, normal, sunDir, viewDir, roughness);
        float light   = diffuse * visibility * ringShadowFactor * 1.18;

        // Blinn-Phong specular (energy-conserving weight by roughness).
        float3 halfVec   = normalize(sunDir + viewDir);
        float  NdotH     = max(dot(normal, halfVec), 0.0);
        float  shininess = mix(2.0, 140.0, 1.0 - roughness);
        float  specFactor = pow(NdotH, shininess) * NdotL * visibility * ringShadowFactor;
            float specMap = 1.0;
            if (uniforms.hasSpecularMap > 0.5) {
                float specLum = mapLuminance(specularTexture.sample(surfaceSampler, surfaceUV).rgb);
                specMap = smoothstep(0.04, 0.92, specLum) * uniforms.specularMapStrength;
            }
            float  specStr    = pow(max(1.0 - roughness, 0.0), 2.5) * 0.45 * specMap;
            float3 specColor = float3(1.0, 0.97, 0.93) * specFactor * specStr;

        float3 tint  = mix(float3(1.0), uniforms.tintColor.rgb, clamp(uniforms.surfaceTintStrength, 0.0, 1.0));
        float3 color = texel.rgb * tint * light + specColor;

        if (uniforms.hasEmissionMap > 0.5) {
            float sunlit = NdotL * visibility * ringShadowFactor;
            float nightFactor = 1.0 - smoothstep(0.018, 0.22, sunlit);
            float3 emission = emissionTexture.sample(surfaceSampler, surfaceUV).rgb
                * uniforms.emissionMapStrength
                * nightFactor;
            color += emission;
        }

        return float4(color, texel.a * uniforms.opacity);
    }

    // ── Ring fragment shader ──────────────────────────────────────────────────
    fragment float4 ringFragment(VertexOut in [[stage_in]],
                                 constant RenderUniforms&   uniforms  [[buffer(1)]],
                                 constant LightingOccluder* occluders  [[buffer(2)]],
                                 constant LightingParameters& lighting  [[buffer(3)]],
                                 texture2d<float>           ringTexture [[texture(0)]],
                                 sampler                    ringSampler [[sampler(0)]]) {
        float radial     = in.uv.x;
        float innerRatio = uniforms.layerKind;
        if (radial < innerRatio) discard_fragment();

        float radialUV = clamp((radial - innerRatio) / max(1.0 - innerRatio, 1e-4), 0.0, 1.0);
        float4 texel   = ringTexture.sample(ringSampler, float2(radialUV, 0.5));
        // Use the alpha channel as the ring mask. RGB can contain color in
        // fully transparent pixels, especially near texture padding.
        float  alpha   = texel.a;
        if (alpha < 0.025) discard_fragment();

        float3 normal    = normalize(in.worldNormal);
        float3 sunDir    = normalize(uniforms.sunDirection.xyz);
        float  direct    = abs(dot(normal, sunDir));
        float  vis       = sphereSunVisibility(in.worldPosition, occluders, lighting);
        // Make Saturn's umbra on the rings read as a deeper shadow instead of
        // a translucent gray overlay.
        float  shadowVis = smoothstep(0.18, 1.0, vis);
        // No ambient in space: rings in Saturn's umbra should be genuinely dark.
        // The 0.0 floor means the only light source is the sun (through vis).
        float  light     = direct * shadowVis * 1.14;
        float  band      = smoothstep(0.08, 0.95, alpha);
        float3 ringBase  = mix(float3(0.42, 0.35, 0.27), uniforms.tintColor.rgb * 1.06, 0.52);
        float3 color     = mix(ringBase * 0.72, ringBase * 1.18, band) * light;
        return float4(color, alpha * uniforms.opacity);
    }

    // ── Screen-space lens flare ───────────────────────────────────────────────
    vertex FlareVertexOut flareVertex(uint vertexID [[vertex_id]],
                                      constant FlareVertex* vertices [[buffer(0)]]) {
        FlareVertex vert = vertices[vertexID];
        FlareVertexOut out;
        out.position = float4(vert.position, 0.0, 1.0);
        out.color = vert.color;
        out.local = vert.local;
        return out;
    }

    fragment float4 flareFragment(FlareVertexOut in [[stage_in]]) {
        float d = length(in.local);
        float falloff = 1.0 - smoothstep(0.0, 1.0, d);
        falloff = falloff * falloff;
        return float4(in.color.rgb, in.color.a * falloff);
    }

    // ── Orbit line shaders ────────────────────────────────────────────────────
    vertex OrbitVertexOut orbitVertex(uint vertexID [[vertex_id]],
                                      constant OrbitVertex*   vertices [[buffer(0)]],
                                      constant OrbitUniforms& uniforms [[buffer(1)]]) {
        OrbitVertex vert = vertices[vertexID];
        OrbitVertexOut out;
        out.position = uniforms.viewProjectionMatrix * float4(vert.position, 1.0);
        out.color    = vert.color;
        return out;
    }

    fragment float4 orbitFragment(OrbitVertexOut in [[stage_in]]) {
        return in.color;
    }
    """#
}
#endif
