#!/usr/bin/python3
#
# Tests for bin/ohmydebn-pdf-sign's commands, which need no display. Small
# PDFs are generated with cairo and reshaped with pikepdf (rotated pages,
# CropBoxes offset inside their MediaBox, a MediaBox that doesn't start at
# 0,0, a /Rotate inherited from the page tree), signed through the real
# command line, and checked from the outside: Poppler's pdftoppm renders
# each page as a viewer shows it, at 72 dpi so one pixel is one point, to
# find where the signature landed, and pdftotext -bbox finds the text.
# Nothing outside a temporary directory is touched: signatures go to a
# temporary XDG_DATA_HOME.
#
# Skipped (exit 0) when python3-pikepdf or Pillow isn't installed, as on a
# machine that hasn't run the OhMyDebn update that brings them in; the
# placement checks also need poppler-utils.

import json
import locale
import math
import os
import random
import shutil
import subprocess
import sys
import tempfile
import time
from importlib.machinery import SourceFileLoader
from importlib.util import module_from_spec, spec_from_loader

REPO_ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
SCRIPT = os.path.join(REPO_ROOT, "bin", "ohmydebn-pdf-sign")

try:
    import cairo
    import pikepdf
    from PIL import Image, ImageChops, ImageDraw, ImageFilter
except ImportError as e:
    print(f"  skip - ohmydebn-pdf-sign's dependencies aren't installed here ({e})")
    sys.exit(0)

HAVE_POPPLER_UTILS = bool(shutil.which("pdftoppm") and shutil.which("pdftotext"))

TESTS_RUN = 0
TESTS_FAILED = 0


def check(desc, condition, detail=""):
    global TESTS_RUN, TESTS_FAILED
    TESTS_RUN += 1
    if condition:
        print(f"  ok - {desc}")
    else:
        print(f"  FAIL - {desc}" + (f": {detail}" if detail else ""))
        TESTS_FAILED += 1


def load_script():
    loader = SourceFileLoader("ohmydebn_pdf_sign", SCRIPT)
    module = module_from_spec(spec_from_loader(loader.name, loader))
    loader.exec_module(module)
    return module


TMP = tempfile.mkdtemp(prefix="test-pdf-sign-")
ENV = dict(os.environ, XDG_DATA_HOME=os.path.join(TMP, "data"), LC_ALL="C.UTF-8", LANG="C.UTF-8")
ENV.pop("DISPLAY", None)
ENV.pop("WAYLAND_DISPLAY", None)
os.environ["XDG_DATA_HOME"] = ENV["XDG_DATA_HOME"]
pdf_sign = load_script()


def run(*args, stdin=None):
    return subprocess.run([sys.executable, SCRIPT, *args], env=ENV, capture_output=True, text=True,
                          input=stdin if stdin is not None else "", timeout=60)


def tmp(name):
    return os.path.join(TMP, name)


def make_pdf(path, pages):
    """pages: [(width, height, label)]. Each page gets its label as text
    near the top-left so the original content can be found afterwards."""
    surface = None
    for w, h, label in pages:
        if surface is None:
            surface = cairo.PDFSurface(path, w, h)
        else:
            surface.set_size(w, h)
        ctx = cairo.Context(surface)
        ctx.select_font_face("Sans")
        ctx.set_font_size(10)
        # Inside every CropBox the tests use.
        ctx.move_to(100, 150)
        ctx.show_text(label)
        surface.show_page()
    surface.finish()


def red_box(png_path):
    """Bounding box (x0, y0, x1, y1) of the pure-red pixels in a render."""
    img = Image.open(png_path).convert("RGB")
    r, g, b = img.split()
    mask = Image.merge("RGB", (r.point(lambda v: 255 if v > 200 else 0), g.point(lambda v: 255 if v < 60 else 0),
                               b.point(lambda v: 255 if v < 60 else 0))).convert("L")
    return mask.point(lambda v: 255 if v > 250 else 0).getbbox()


def render(pdf, page, prefix):
    """Render one page as shown (CropBox, rotation applied) at 72 dpi."""
    subprocess.run(["pdftoppm", "-cropbox", "-r", "72", "-png", "-f", str(page), "-l", str(page), "-singlefile",
                    pdf, prefix], check=True, capture_output=True)
    return prefix + ".png"


def words(pdf, page):
    """{word: (xMin, yMin, xMax, yMax)} on a page, as shown."""
    out = subprocess.run(["pdftotext", "-cropbox", "-bbox", "-f", str(page), "-l", str(page), pdf, "-"],
                         check=True, capture_output=True, text=True).stdout
    found = {}
    for line in out.splitlines():
        line = line.strip()
        if line.startswith("<word "):
            attrs = dict(part.split("=", 1) for part in line[6:line.index(">")].split())
            text = line[line.index(">") + 1:line.rindex("</word>")]
            found[text] = tuple(float(attrs[k].strip('"')) for k in ("xMin", "yMin", "xMax", "yMax"))
    return found


def sha(path):
    import hashlib

    with open(path, "rb") as f:
        return hashlib.sha256(f.read()).hexdigest()


def near(a, b, tol):
    return all(abs(x - y) <= tol for x, y in zip(a, b))


# ---------- a signature to place ----------

print("add-signature / signatures")

# A red rectangle on transparency: already transparent, so used as it
# is, only cropped (to the rectangle plus a 4 px margin).
img = Image.new("RGBA", (240, 140), (0, 0, 0, 0))
img.paste((255, 0, 0, 255), (20, 20, 220, 120))
img.save(tmp("red.png"))
r = run("add-signature", "Red", tmp("red.png"))
check("add-signature saves a transparent PNG", r.returncode == 0, r.stderr)
saved = os.path.join(ENV["XDG_DATA_HOME"], "ohmydebn", "signatures", "Red.png")
check("it's saved under ~/.local/share/ohmydebn/signatures/<name>.png", os.path.isfile(saved))
with Image.open(saved) as s:
    check("a transparent PNG is only cropped to its ink", s.size == (208, 108), str(s.size))

r = run("signatures")
check("signatures lists it", r.stdout.splitlines() == ["Red"], r.stdout)
r = run("signatures", "--json")
check("signatures --json marks the last used", json.loads(r.stdout)[0]["last_used"] is True, r.stdout)
for bad in ("../evil", ".hidden", "a/b", ""):
    r = run("add-signature", bad, tmp("red.png"))
    check(f"add-signature refuses the name {bad!r}", r.returncode == 1 and not os.path.exists(
        os.path.join(TMP, "evil.png")), r.stderr)
r = run("add-signature", "Nothing", tmp("missing.png"))
check("add-signature reports an unreadable image", r.returncode == 1 and "Can't read" in r.stderr, r.stderr)

# Signature box in the source image's pixels, scaled into points: the
# saved PNG is 208 x 108 with the red 200 x 100 inset 4 px, placed 120 pt
# wide.
SIG_W = 120.0
SCALE = SIG_W / 208
SIG_H = 108 * SCALE


def expected_red(x, y):
    return (x + 4 * SCALE, y + 4 * SCALE, x + 204 * SCALE, y + 104 * SCALE)


# ---------- placement on every page shape ----------

print("sign: placement")

# (label, MediaBox, CropBox or None, /Rotate). An inherited /Rotate
# can't be built here: pikepdf pushes inherited attributes onto the pages
# when it saves (and when it reads .pages), so page_geometry()'s own
# lookup is tested on plain dictionaries under "geometry" instead.
SHAPES = [
    ("plain", [0, 0, 612, 792], None, 0),
    ("rot90", [0, 0, 612, 792], None, 90),
    ("rot180", [0, 0, 612, 792], None, 180),
    ("rot270", [0, 0, 612, 792], None, 270),
    ("crop", [0, 0, 612, 792], [60, 110, 540, 700], 0),
    ("crop90", [0, 0, 612, 792], [60, 110, 540, 700], 90),
    ("crop270", [0, 0, 612, 792], [45, 30, 600, 760], 270),
    ("offsetmedia", [-50, -80, 562, 712], [0, 0, 500, 650], 0),
    ("negrotate", [0, 0, 612, 792], None, -90),
]
make_pdf(tmp("base.pdf"), [(612, 792, f"ORIG{label}") for label, *_ in SHAPES])
with pikepdf.open(tmp("base.pdf")) as pdf:
    for page, (label, media, crop, rotate) in zip(pdf.pages, SHAPES):
        page.obj.MediaBox = pikepdf.Array(media)
        if crop:
            page.obj.CropBox = pikepdf.Array(crop)
        if rotate:
            page.obj.Rotate = rotate
    pdf.save(tmp("shapes.pdf"))

r = run("pages", tmp("shapes.pdf"), "--json")
pages = json.loads(r.stdout)["pages"] if r.returncode == 0 else []
check("pages lists every page", len(pages) == len(SHAPES), r.stderr)
expected_sizes = {"plain": (612, 792), "rot90": (792, 612), "crop": (480, 590), "crop90": (590, 480),
                  "crop270": (730, 555), "offsetmedia": (500, 650), "negrotate": (792, 612)}
for n, (label, *_rest) in enumerate(SHAPES):
    if label in expected_sizes and n < len(pages):
        got = (pages[n]["width"], pages[n]["height"])
        check(f"pages: {label} is {expected_sizes[label]} as shown", got == expected_sizes[label], str(got))

items = []
for n, (label, *_rest) in enumerate(SHAPES, 1):
    items.append({"signature": "Red", "page": n, "x": 100 + n, "y": 200 + n, "width": SIG_W})
    items.append({"text": f"MARK{label}", "page": n, "x": 50, "y": 300, "size": 14})
with open(tmp("items.json"), "w") as f:
    json.dump(items, f)

before = sha(tmp("shapes.pdf"))
r = run("sign", tmp("shapes.pdf"), tmp("shapes-signed.pdf"), "--items", tmp("items.json"))
check("sign succeeds", r.returncode == 0, r.stderr)
check("the original is byte-identical afterwards", sha(tmp("shapes.pdf")) == before)

if HAVE_POPPLER_UTILS and r.returncode == 0:
    for n, (label, *_rest) in enumerate(SHAPES, 1):
        box = red_box(render(tmp("shapes-signed.pdf"), n, tmp(f"render-{n}")))
        want = expected_red(100 + n, 200 + n)
        check(f"{label}: the signature lands where it was placed, upright", box is not None and near(box, want, 1.5),
              f"got {box}, want {tuple(round(v, 1) for v in want)}")
        found = words(tmp("shapes-signed.pdf"), n)
        mark = found.get(f"MARK{label}")
        # Pango's logical box starts above the glyphs; pdftotext's box
        # starts at the font's ascent, so allow a few points vertically.
        check(f"{label}: the text lands where it was placed", mark is not None and abs(mark[0] - 50) < 1.5
              and abs(mark[1] - 300) < 4, f"got {mark}")
        orig_before = words(tmp("shapes.pdf"), n).get(f"ORIG{label}")
        orig_after = found.get(f"ORIG{label}")
        check(f"{label}: the original text is still there, unmoved", orig_before is not None
              and orig_after is not None and near(orig_before, orig_after, 0.01), f"{orig_before} vs {orig_after}")
else:
    print("  skip - poppler-utils isn't installed, so placement isn't checked")

with pikepdf.open(tmp("shapes.pdf")) as src, pikepdf.open(tmp("shapes-signed.pdf")) as out:
    same_boxes = all(list(a.obj.MediaBox) == list(b.obj.MediaBox) and a.obj.get("/CropBox") == b.obj.get("/CropBox")
                     for a, b in zip(src.pages, out.pages))
    check("the signed copy keeps every page's boxes", same_boxes)
    contents_kept = True
    for a, b in zip(src.pages, out.pages):
        a.contents_coalesce()
        original = a.obj.Contents.read_bytes().strip()
        b.contents_coalesce()
        if original not in b.obj.Contents.read_bytes():
            contents_kept = False
    check("each page's own content stream is kept as it was (not re-rendered)", contents_kept)
    check("the signed copy has the same number of pages", len(src.pages) == len(out.pages))

# ---------- items.json handling ----------

print("sign: items")

make_pdf(tmp("two.pdf"), [(612, 792, "ONE"), (595, 842, "TWO")])
bad = [
    {"signature": "Nobody", "page": 1, "x": 10, "y": 10},
    {"text": "hi", "page": 9, "x": 10, "y": 10},
    {"text": "hi", "page": 1, "x": 10},
    {"text": "hi", "date": True, "page": 1, "x": 10, "y": 10},
    {"text": "far", "page": 1, "x": 5000, "y": 10},
    {"signature": "Red", "page": 1, "x": 10, "y": 10, "width": -5},
]
with open(tmp("bad.json"), "w") as f:
    json.dump(bad, f)
r = run("sign", tmp("two.pdf"), tmp("two-signed.pdf"), "--items", tmp("bad.json"))
check("bad items fail the run", r.returncode == 1)
check("every bad item is reported at once", all(f"item {n}" in r.stderr for n in range(1, len(bad) + 1)), r.stderr)
check("nothing is written when an item is bad", not os.path.exists(tmp("two-signed.pdf")))
check("a missing signature names the saved ones", "saved: Red" in r.stderr, r.stderr)

r = run("sign", tmp("two.pdf"), tmp("two.pdf"), "--items", tmp("items.json"))
check("sign refuses to write over the original", r.returncode == 1 and "original" in r.stderr, r.stderr)
r = run("sign", tmp("two.pdf"), tmp("nowhere/out.pdf"), "--items", "-",
        stdin=json.dumps([{"text": "x", "page": 1, "x": 10, "y": 10}]))
check("sign reports a missing output folder plainly", r.returncode == 1 and "doesn't exist" in r.stderr
      and "Traceback" not in r.stderr, r.stderr)
os.symlink(tmp("two.pdf"), tmp("alias.pdf"))
r = run("sign", tmp("two.pdf"), tmp("alias.pdf"), "--items", tmp("items.json"))
check("sign refuses a link to the original too", r.returncode == 1 and os.path.islink(tmp("alias.pdf")), r.stderr)

items = {"items": [
    {"date": True, "page": 2, "x": 300, "y": 100},
    {"signature": "Red", "page": 2, "x": 72, "bottom": 700, "height": 54},
    {"text": "Line one\nLine two", "page": 1, "x": 72, "y": 72, "size": 20, "color": "#0000ff"},
]}
r = run("sign", tmp("two.pdf"), tmp("two-signed.pdf"), "--items", "-", "--json", stdin=json.dumps(items))
check("sign reads items from standard input and reports JSON", r.returncode == 0 and json.loads(r.stdout)["items"] == 3,
      r.stderr + r.stdout)
if HAVE_POPPLER_UTILS and r.returncode == 0:
    found = words(tmp("two-signed.pdf"), 2)
    locale.setlocale(locale.LC_TIME, "C.UTF-8")
    today = time.strftime("%x")
    check(f"a date item is today in the locale's format ({today})", today in found, str(list(found)))
    box = red_box(render(tmp("two-signed.pdf"), 2, tmp("render-two")))
    # height 54 -> width 104; "bottom" is the item's lower edge.
    h = 54.0
    s = h / 108
    want = (72 + 4 * s, 700 - h + 4 * s, 72 + 204 * s, 700 - h + 104 * s)
    check("bottom places a signature's lower edge, height keeps its proportions", box is not None
          and near(box, want, 1.5), f"got {box}, want {want}")
    page1 = words(tmp("two-signed.pdf"), 1)
    check("multi-line text keeps both lines", "one" in page1 and "two" in page1 and page1["two"][1] > page1["one"][1],
          str(page1))

# ---------- digital signatures ----------

print("sign: digitally signed input")

with pikepdf.open(tmp("two.pdf")) as pdf:
    sig = pdf.make_indirect(pikepdf.Dictionary(Type=pikepdf.Name.Sig, Filter=pikepdf.Name("/Adobe.PPKLite"),
                                               Contents=pikepdf.String(b"\0" * 16)))
    field = pdf.make_indirect(pikepdf.Dictionary(FT=pikepdf.Name.Sig, T=pikepdf.String("Signature1"), V=sig))
    pdf.Root.AcroForm = pikepdf.Dictionary(Fields=pikepdf.Array([field]), SigFlags=3)
    pdf.save(tmp("sealed.pdf"))
r = run("sign", tmp("sealed.pdf"), tmp("sealed-signed.pdf"), "--items", "-",
        stdin=json.dumps([{"text": "x", "page": 1, "x": 10, "y": 10}]))
check("signing a digitally signed PDF warns that its signature breaks",
      r.returncode == 0 and "digital signature" in r.stderr, r.stderr)
r = run("sign", tmp("two.pdf"), tmp("plain-signed.pdf"), "--items", "-",
        stdin=json.dumps([{"text": "x", "page": 1, "x": 10, "y": 10}]))
check("an unsigned PDF gets no such warning", r.returncode == 0 and "digital signature" not in r.stderr, r.stderr)
with pikepdf.open(tmp("two.pdf")) as pdf:
    pdf.Root.AcroForm = pikepdf.Dictionary(Fields=pikepdf.Array([pdf.make_indirect(pikepdf.Dictionary(
        FT=pikepdf.Name.Sig, T=pikepdf.String("Empty")))]))
    check("an empty signature field doesn't count as signed", not pdf_sign.has_digital_signature(pdf))

# ---------- lifting a signature off its paper ----------

print("threshold: a synthetic photo")

# A phone photo: warm paper lit unevenly (bright top-left, shadow toward
# the bottom-right), sensor noise, slight blur, and a blue pen stroke.
random.seed(7)
W, H = 900, 600
across = Image.linear_gradient("L").rotate(90).resize((W, H))
down = Image.linear_gradient("L").resize((W, H))
paper = ImageChops.add(across, down, 2.0).point(lambda v: 238 - int(v * 0.33))  # 238 bright .. ~154 dim
photo = Image.merge("RGB", (paper, paper.point(lambda v: v - 4), paper.point(lambda v: v - 14)))
noise = Image.effect_noise((W, H), 6)
photo = Image.merge("RGB", [ImageChops.add(c, noise, 1.0, -128) for c in photo.split()])
draw = ImageDraw.Draw(photo)
stroke = [(150 + i * 3, 300 + int(80 * math.sin(i / 12))) for i in range(200)]
draw.line(stroke, fill=(35, 50, 160), width=8)
photo = photo.filter(ImageFilter.GaussianBlur(1))
photo.save(tmp("photo.jpg"), quality=92)

with Image.open(tmp("photo.jpg")) as src:
    out = pdf_sign.extract_signature(src)
alpha = out.getchannel("A")
check("the result is cropped to the stroke", abs(out.width - (597 + 8 + 8)) < 30 and abs(out.height - (160 + 8 + 8)) < 30,
      str(out.size))
corners = [alpha.getpixel(p) for p in ((0, 0), (out.width - 1, 0), (0, out.height - 1), (out.width - 1, out.height - 1))]
check("the paper is gone, shadowed corner included", max(corners) == 0, str(corners))
histogram = alpha.histogram()
paper_share = histogram[0] / sum(histogram)
check("most of the cropped area is transparent paper", paper_share > 0.6, f"{paper_share:.2f}")
# An 8 px line about 650 px long, less its blurred edges.
solid = sum(1 for v in alpha.getdata() if v == 255)
check("there is solid ink, roughly the stroke's area", 3000 < solid < 9000, str(solid))
r, g, b, _a = out.getpixel(next((x, y) for y in range(out.height) for x in range(out.width)
                                if alpha.getpixel((x, y)) == 255))
check("blue ink stays blue", b > r + 60 and b > g + 60, str((r, g, b)))

with Image.open(tmp("photo.jpg")) as src:
    more = pdf_sign.extract_signature(src, threshold=90)
    less = pdf_sign.extract_signature(src, threshold=10)
count = lambda im: sum(1 for v in im.getchannel("A").getdata() if v > 0)  # noqa: E731
check("a higher paper threshold keeps less", count(more) < count(less), f"{count(more)} vs {count(less)}")

# A hard shadow edge (a hand or phone over the page) leaves a faint line
# at the default threshold; More is what removes it.
shadowed = photo.copy()
shadowed.paste(Image.eval(photo.crop((0, 0, W, 120)), lambda v: v - 45), (0, 0))
with_edge = pdf_sign.extract_signature(shadowed, threshold=80)
check("a higher threshold removes a hard shadow edge",
      with_edge.height < 200 and with_edge.getchannel("A").getpixel((5, 5)) == 0, str(with_edge.size))

blank = Image.new("RGB", (400, 300), (230, 228, 220))
try:
    pdf_sign.extract_signature(blank)
    check("a photo with no ink is refused", False)
except pdf_sign.SignError:
    check("a photo with no ink is refused", True)

r = run("add-signature", "Photo", tmp("photo.jpg"))
check("add-signature takes a JPEG photo", r.returncode == 0 and "Photo" in run("signatures").stdout, r.stderr)

# ---------- geometry helpers ----------

print("geometry")

parent = pikepdf.Dictionary(Type=pikepdf.Name.Pages, Rotate=90, MediaBox=[0, 0, 300, 400])
leaf = pikepdf.Dictionary(Type=pikepdf.Name.Page, Parent=parent)
check("/Rotate and /MediaBox are inherited from the page tree",
      pdf_sign.page_geometry(leaf) == ((0, 0, 300, 400), (0, 0, 300, 400), 90))
check("a CropBox is clipped to its MediaBox",
      pdf_sign.page_geometry(pikepdf.Dictionary(MediaBox=[0, 0, 100, 100], CropBox=[-10, 20, 300, 90]))[1]
      == (0, 20, 100, 90))
check("/Rotate snaps to quarter turns and wraps",
      pdf_sign.page_geometry(pikepdf.Dictionary(MediaBox=[0, 0, 100, 100], Rotate=-90))[2] == 270)
check("a reversed box is normalised",
      pdf_sign.page_geometry(pikepdf.Dictionary(MediaBox=[100, 200, 0, 0]))[0] == (0, 0, 100, 200))
check("a signed copy is named <name>-signed.pdf", pdf_sign.default_signed_path("/a/lease.pdf") == "/a/lease-signed.pdf")

shutil.rmtree(TMP)
print(f"{TESTS_RUN - TESTS_FAILED}/{TESTS_RUN} passed")
sys.exit(1 if TESTS_FAILED else 0)
