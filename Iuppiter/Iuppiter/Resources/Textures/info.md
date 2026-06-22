
High-resolution Solar System Scope textures:

These files are distributed by Solar System Scope under the Creative Commons Attribution 4.0 International license.

- HighRes/8k_sun.jpg: https://www.solarsystemscope.com/textures/download/8k_sun.jpg
- HighRes/8k_mercury.jpg: https://www.solarsystemscope.com/textures/download/8k_mercury.jpg
- HighRes/4k_venus_atmosphere.jpg: https://www.solarsystemscope.com/textures/download/4k_venus_atmosphere.jpg
- Maps/8k_earth_nightmap.jpg: https://www.solarsystemscope.com/textures/download/8k_earth_nightmap.jpg
- HighRes/8k_moon.jpg: https://www.solarsystemscope.com/textures/download/8k_moon.jpg
- HighRes/8k_mars.jpg: https://www.solarsystemscope.com/textures/download/8k_mars.jpg
- HighRes/8k_jupiter.jpg: https://www.solarsystemscope.com/textures/download/8k_jupiter.jpg
- HighRes/8k_saturn.jpg: https://www.solarsystemscope.com/textures/download/8k_saturn.jpg
- HighRes/8k_saturn_ring_alpha.png: https://www.solarsystemscope.com/textures/download/8k_saturn_ring_alpha.png
- Maps/8k_earth_normal_map.tif: https://www.solarsystemscope.com/textures/download/8k_earth_normal_map.tif
- Maps/8k_earth_specular_map.tif: https://www.solarsystemscope.com/textures/download/8k_earth_specular_map.tif

No higher-resolution Solar System Scope Uranus or Neptune maps were available; their published downloads are still 2k.

Physically accurate Earth texture:

- HighRes/nasa_blue_marble_ng_8k.jpg: https://neo.gsfc.nasa.gov/servlet/RenderData?cs=rgb&format=JPEG&height=4096&si=526308&width=8192

Credit: NASA Earth Observations / Blue Marble Next Generation. Blue Marble Next Generation data courtesy of Reto Stockli (NASA/GSFC) and NASA's Earth Observatory.

Live Earth imagery and specular maps:

The app fetches live Earth true-color imagery from NASA GIBS at runtime. The cloud-covered true-color base map is requested daily and the specular map refreshes while Earth is being rendered.

- True color: https://gibs.earthdata.nasa.gov/wms/epsg4326/best/wms.cgi
- Specular: https://clouds.matteason.co.uk/images/8192x4096/specular.jpg
- Original live cloud service: https://github.com/matteason/live-cloud-maps

Attribution: Contains modified EUMETSAT data. The Live Cloud Maps code and generated images are released under CC0 1.0 by Matt Eason.


Callisto:

https://bjj.mmedia.is/data/callisto/details.html

From Author:

| **Feature**                     | **Coordinate (USGS map)** | **Coordinate (my map)**     |
| ------------------------------- | ------------------------- | --------------------------- |
| Dark spot in Valhalla           | (3207,771)                | (3205,770)                  |
| Crater in Asgard                | (2290,632)                | (2291,633)                  |
| North of Adlinda                | (3558,1289)               | (3557,1289)                 |
| Crater near the north pole      | (2724,118)                | (2724,117)                  |
| Crater very near the north pole | (3550,54)                 | (3548,48)                   |
| Crater near the equator         | (1669,911)                | (1673,909)                  |
| Near an equatorial crater       | (471,872)                 | (472,872)                   |
| Bright creater rim in the south | (216,1275)                | (215,1276)                  |
| Crater north of the equator     | (1793,717)                | (1788,713) and (1798,716) * |


Enceladus:

a=256.2 km,b=251.4 km,c=248.6 km


Ganymede

**Positive-west** longitude.


Io:

Positive-west longitude

Mimas:

NASA/JPL’s **2014 Cassini global mosaic, PIA18437**:

Phobos:

**positive-east longitude**

Deimos:

**Philip Stooke / NASA PDS improved Deimos map**

- **7200 × 3600**
- Equirectangular/simple cylindrical
- Viking and Mariner 9 imagery
- Adds details from the two 2009 MRO HiRISE observations
- Corrected geometry near 60∘60^\circ60∘E
- 0∘0^\circ0∘ longitude at the centre

(Also 3D object, high res one available)

Pluto:

> The DEM contains elevations in metres, while Blender scene units may represent kilometres or arbitrary units. Pluto’s reference radius is approximately:

Titan:

This one is complicated. the true surface detail is hidden from view via thick atmosphere.

The atmosphere is 95% nitrogen and 5% methane. Extending 600 km above its surface.
With surface radius represented as 1, the physical atmosphere extends to around 
$$1+\frac{600}{2575} \approx 1.233$$
Main atmosphere: 
- Warm amber/muted orange
- Strong scattering
- Density concentrated close to surface
Main aerosol haze
- Denser orange-brown layer
- Hides surface detail
- Create Titan's featureless golden appearance
Upper haze
- Cassini observed thin haze around 500km altitude, corresponds to approximately
$$1+\frac{500}{2575} \approx 1.194$$
- Thin, low opacity shell around $1.19$
- slightly bluish at illuminated limb
- NASA image shows main haze as orange, smaller high altitude particles produce blue fringe. 
