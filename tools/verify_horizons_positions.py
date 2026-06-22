#!/usr/bin/env python3
from __future__ import annotations

import datetime as dt
import json
import math
import subprocess
import tempfile
from pathlib import Path
from urllib.parse import urlencode
from urllib.request import Request, urlopen


ROOT = Path(__file__).resolve().parents[1]
AU_KM = 149_597_870.7
SCENE_UNITS_PER_AU = 6.0

BODY_IDS = {
    "mercury": 199, "venus": 299, "earth": 399, "moon": 301,
    "mars": 499, "phobos": 401, "deimos": 402,
    "jupiter": 599, "io": 501, "europa": 502, "ganymede": 503, "callisto": 504,
    "amalthea": 505, "himalia": 506, "elara": 507, "pasiphae": 508,
    "sinope": 509, "lysithea": 510, "carme": 511, "ananke": 512,
    "leda": 513, "thebe": 514, "adrastea": 515, "metis": 516,
    "saturn": 699, "mimas": 601, "enceladus": 602, "tethys": 603,
    "dione": 604, "rhea": 605, "titan": 606, "hyperion": 607,
    "iapetus": 608, "phoebe": 609, "janus": 610, "epimetheus": 611,
    "helene": 612, "telesto": 613, "calypso": 614, "atlas": 615,
    "prometheus": 616, "pandora": 617, "pan": 618, "methone": 632,
    "pallene": 633, "anthe": 649,
    "uranus": 799, "ariel": 701, "umbriel": 702, "titania": 703,
    "oberon": 704, "miranda": 705, "cordelia": 706, "ophelia": 707,
    "bianca": 708, "cressida": 709, "desdemona": 710, "juliet": 711,
    "portia": 712, "rosalind": 713, "belinda": 714, "puck": 715,
    "perdita": 725, "mab": 726,
    "neptune": 899, "triton": 801, "nereid": 802, "naiad": 803,
    "thalassa": 804, "despina": 805, "galatea": 806, "larissa": 807,
    "proteus": 808, "halimede": 809, "psamathe": 810, "sao": 811,
    "laomedeia": 812, "neso": 813,
    "pluto": 999, "charon": 901, "nix": 902, "hydra": 903,
    "kerberos": 904, "styx": 905,
}

CENTERS = {
    "sun": "500@10",
    "earth": "500@399",
    "mars": "500@499",
    "jupiter": "500@599",
    "saturn": "500@699",
    "uranus": "500@799",
    "neptune": "500@899",
    "pluto": "500@9",
}


def compile_and_dump_positions() -> tuple[str, dict[str, dict[str, object]]]:
    source = """
import Foundation

@main
struct DumpPositions {
    static func main() {
        let now = Date()
        let fmt = ISO8601DateFormatter()
        fmt.timeZone = TimeZone(secondsFromGMT: 0)
        let j2000 = DateComponents(calendar: Calendar(identifier: .gregorian), timeZone: TimeZone(abbreviation: "UTC"), year: 2000, month: 1, day: 1, hour: 12).date!
        let days = now.timeIntervalSince(j2000) / 86400.0
        let elapsed = days / 5.0
        let snapshot = SolarSystemSimulation.snapshot(elapsedSeconds: elapsed, selectedBodyID: "sun", options: NativeRenderOptions(showMoons: true, showMinorMoons: true, showProcedural: true, showLabels: true, showOrbits: true))
        print("utc,\\(fmt.string(from: now))")
        for state in snapshot.states {
            let p = state.position
            print("\\(state.body.id),\\(state.body.parentID ?? ""),\\(p.x),\\(p.y),\\(p.z)")
        }
    }
}
"""
    with tempfile.TemporaryDirectory() as tmp:
        tmp_path = Path(tmp)
        dump_swift = tmp_path / "DumpPositions.swift"
        binary = tmp_path / "dump_positions"
        dump_swift.write_text(source)
        subprocess.run(
            [
                "swiftc",
                str(ROOT / "Iuppiter/Iuppiter/Models/NativeCelestialBody.swift"),
                str(ROOT / "Iuppiter/Iuppiter/Simulation/SolarSystemSimulation.swift"),
                str(dump_swift),
                "-o",
                str(binary),
            ],
            check=True,
            cwd=ROOT,
        )
        output = subprocess.check_output([str(binary)], text=True)

    utc = ""
    rows: dict[str, dict[str, object]] = {}
    for line in output.splitlines():
        parts = line.split(",")
        if parts[0] == "utc":
            utc = parts[1]
        else:
            rows[parts[0]] = {
                "parent": parts[1],
                "position": tuple(float(value) for value in parts[2:5]),
            }
    return utc, rows


def app_to_horizons_km(position: tuple[float, float, float]) -> tuple[float, float, float]:
    x, y, z = position
    scale = AU_KM / SCENE_UNITS_PER_AU
    return -x * scale, z * scale, -y * scale


def horizon_vector(body_id: int, center: str, utc: str) -> tuple[float, float, float]:
    start = dt.datetime.fromisoformat(utc.replace("Z", "+00:00"))
    params = {
        "format": "json",
        "COMMAND": str(body_id),
        "OBJ_DATA": "NO",
        "MAKE_EPHEM": "YES",
        "EPHEM_TYPE": "VECTORS",
        "CENTER": center,
        "START_TIME": f"'{start:%Y-%b-%d %H:%M}'",
        "STOP_TIME": f"'{start + dt.timedelta(minutes=1):%Y-%b-%d %H:%M}'",
        "STEP_SIZE": "1m",
        "VEC_TABLE": "2",
        "CSV_FORMAT": "YES",
        "VEC_CORR": "NONE",
        "OUT_UNITS": "KM-S",
    }
    url = "https://ssd.jpl.nasa.gov/api/horizons.api?" + urlencode(params)
    request = Request(url, headers={"User-Agent": "Iuppiter-Horizons-Verifier/1.0"})
    with urlopen(request, timeout=30) as response:
        data = json.loads(response.read().decode("utf-8"))
    if "error" in data:
        raise RuntimeError(data["error"])
    text = data["result"]
    fields = [field.strip() for field in text.split("$$SOE")[1].split("$$EOE")[0].strip().splitlines()[0].split(",")]
    return tuple(float(fields[index]) for index in (2, 3, 4))


def subtract(a: tuple[float, float, float], b: tuple[float, float, float]) -> tuple[float, float, float]:
    return tuple(x - y for x, y in zip(a, b))


def norm(vector: tuple[float, float, float]) -> float:
    return math.sqrt(sum(value * value for value in vector))


def angle_degrees(a: tuple[float, float, float], b: tuple[float, float, float]) -> float:
    denom = norm(a) * norm(b)
    if denom == 0:
        return 0.0
    cosine = max(-1.0, min(1.0, sum(x * y for x, y in zip(a, b)) / denom))
    return math.degrees(math.acos(cosine))


def main() -> None:
    utc, rows = compile_and_dump_positions()
    results: list[tuple[float, float, float, str]] = []
    skipped = ["daphnis: Horizons has no current ephemeris after 2018; catalog uses JPL satellite mean elements"]

    for body_id, horizons_id in BODY_IDS.items():
        if body_id not in rows:
            continue
        parent = str(rows[body_id]["parent"])
        app = app_to_horizons_km(rows[body_id]["position"])  # type: ignore[arg-type]

        if parent and parent in rows:
            app_parent = app_to_horizons_km(rows[parent]["position"])  # type: ignore[arg-type]
            app_vector = subtract(app, app_parent)
            center = "500@999" if body_id == "charon" else CENTERS[parent]
        else:
            app_vector = app
            center = "500@10"

        horizons = horizon_vector(horizons_id, center, utc)
        if body_id == "pluto":
            app_vector = app
            horizons = horizon_vector(999, "500@10", utc)

        distance_error_km = abs(norm(app_vector) - norm(horizons))
        relative_distance_error = distance_error_km / max(norm(horizons), 1.0)
        results.append((angle_degrees(app_vector, horizons), relative_distance_error, distance_error_km, body_id))

    results.sort(reverse=True)
    print(f"UTC: {utc}")
    print(f"Checked: {len(results)} bodies")
    print("Worst angular errors:")
    for angle, relative, distance_km, body_id in results[:15]:
        print(f"{body_id:12s} angle={angle:8.4f} deg  rel_dist={relative:10.6g}  abs_dist={distance_km:10.3f} km")
    print("Skipped:")
    for item in skipped:
        print(f"  {item}")


if __name__ == "__main__":
    main()
