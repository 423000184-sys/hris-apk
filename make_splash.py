from PIL import Image
import math

SRC = "assets/images/logo.png"
OUT = "android/app/src/main/res/drawable-nodpi/logo1.png"
S = 1152
R = 350  # ligtas na radius (bilog ay 384)

logo = Image.open(SRC).convert("RGBA")
logo = logo.crop(logo.split()[3].getbbox())

# sukatin ang pinakamalayong pixel mula sa gitna
probe = logo.copy()
probe.thumbnail((300, 300))
a = probe.split()[3].load()
cx, cy = probe.width / 2, probe.height / 2
d = 0
for y in range(probe.height):
    for x in range(probe.width):
        if a[x, y] > 10:
            d = max(d, math.hypot(x - cx, y - cy))

k = R / (d * logo.width / probe.width)
logo = logo.resize((int(logo.width * k), int(logo.height * k)), Image.LANCZOS)

canvas = Image.new("RGBA", (S, S), (0, 0, 0, 0))
canvas.paste(logo, ((S - logo.width) // 2, (S - logo.height) // 2), logo)
canvas.save(OUT)
print("saved", OUT, "size", logo.size)
