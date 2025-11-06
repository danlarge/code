#splod download_torrents.py
from playwright.sync_api import sync_playwright, TimeoutError as PWTimeout
import time
import os
from urllib.parse import urlparse
from pathlib import Path

# ---- CONFIG ----
DOWNLOAD_DIR = Path.cwd() / "downloads"
DOWNLOAD_DIR.mkdir(exist_ok=True)
HEADLESS = False            # set True if you need headless; for debugging use False
RETRY_COUNT = 2
CLICK_TIMEOUT_MS = 10000    # how long to wait for button to appear
NAV_TIMEOUT_MS = 20000
REQUEST_DELAY = 1.0         # seconds between page loads to be polite

# Optional: If the test site requires authentication you can load pre-saved cookies here.
# Example: cookies = [{"name":"sid","value":"...","domain":"gay-torrents.net", ...}, ...]
# Set COOKIES = None if not used.
COOKIES = [
    {
        "name": "manlyman",
        "value": "535",
        "domain": "www.gay-torrents.net",
        "path": "/latest",
        "secure": False,
        "httpOnly": False,
        "expires": 1762473599,
    },
    {
        "name": "HstCfa4403859",
        "value": "1762456004334",
        "domain": "www.gay-torrents.net",
        "path": "/",
        "secure": False,
        "httpOnly": False,
        "expires": 1793992004,
    },
    {
        "name": "HstCla4403859",
        "value": "1762456004334",
        "domain": "www.gay-torrents.net",
        "path": "/",
        "secure": False,
        "httpOnly": False,
        "expires": 1793992004,
    },
    {
        "name": "HstCmu4403859",
        "value": "1762456004334",
        "domain": "www.gay-torrents.net",
        "path": "/",
        "secure": False,
        "httpOnly": False,
        "expires": 1793992004,
    },
    {
        "name": "HstPn4403859",
        "value": "1",
        "domain": "www.gay-torrents.net",
        "path": "/",
        "secure": False,
        "httpOnly": False,
        "expires": 1793992004,
    },
    {
        "name": "HstPt4403859",
        "value": "1",
        "domain": "www.gay-torrents.net",
        "path": "/",
        "secure": False,
        "httpOnly": False,
        "expires": 1793992004,
    },
    {
        "name": "HstCnv4403859",
        "value": "1",
        "domain": "www.gay-torrents.net",
        "path": "/",
        "secure": False,
        "httpOnly": False,
        "expires": 1793992004,
    },
    {
        "name": "HstCns4403859",
        "value": "1",
        "domain": "www.gay-torrents.net",
        "path": "/",
        "secure": False,
        "httpOnly": False,
        "expires": 1793992004,
    },
    {
        "name": "ENvbb_lastvisit",
        "value": "1762456131",
        "domain": "www.gay-torrents.net",
        "path": "/",
        "secure": True,
        "httpOnly": False,
        "expires": 1793992131,
    },
    {
        "name": "ENvbb_lastactivity",
        "value": "0",
        "domain": "www.gay-torrents.net",
        "path": "/",
        "secure": True,
        "httpOnly": False,
        "expires": 1793992133,
    },
    {
        "name": "ENvbb_userid",
        "value": "1151205",
        "domain": "www.gay-torrents.net",
        "path": "/",
        "secure": True,
        "httpOnly": False,
        "expires": 1793992133,
    },
    {
        "name": "ENvbb_password",
        "value": "53f6df34bd3242e1695858e121c6adad",
        "domain": "www.gay-torrents.net",
        "path": "/",
        "secure": True,
        "httpOnly": False,
        "expires": 1793992133,
    },
    {
        "name": "ENvbb_sessionhash",
        "value": "b4d66ce16c4004e38d5e377474161f58",
        "domain": "www.gay-torrents.net",
        "path": "/",
        "secure": False,
        "httpOnly": False,
        # session cookie: no "expires"
    },
    {
        "name": "manlyman",
        "value": "862",
        "domain": "www.gay-torrents.net",
        "path": "/",
        "secure": False,
        "httpOnly": False,
        "expires": 1762473599,
    },
]

# ---- INPUT LIST (as provided) ----
URLS = [
    "https://www.gay-torrents.net/torrentdetails.php?torrentid=4983212c28be6a6a258658fb4f7b32d0ab155d7de033bc5b",
    "https://www.gay-torrents.net/torrentdetails.php?torrentid=47e929eed7be5e86258658fb4f7b32d0244b233b100fe2c5",
    "https://www.gay-torrents.net/torrentdetails.php?torrentid=681542b0ab723d71258658fb4f7b32d09b41399cfc490d93",
    "https://www.gay-torrents.net/torrentdetails.php?torrentid=b0d613b49378c097258658fb4f7b32d010326db1cd74761c",
    "https://www.gay-torrents.net/torrentdetails.php?torrentid=93900ec77caabdb9258658fb4f7b32d08563042c1f0f6f88",
    "https://www.gay-torrents.net/torrentdetails.php?torrentid=32f54344eecf3869258658fb4f7b32d09db809a8f44c3065",
    "https://www.gay-torrents.net/torrentdetails.php?torrentid=7726b1554c63fd78258658fb4f7b32d054e5417f2c34c1f8",
    "https://www.gay-torrents.net/torrentdetails.php?torrentid=19762f0abcb9d248258658fb4f7b32d0e7637470a78c2a57",
    "https://www.gay-torrents.net/torrentdetails.php?torrentid=c9959813dd3d520c258658fb4f7b32d056c4a560a2331b24",
    "https://www.gay-torrents.net/torrentdetails.php?torrentid=94c2aa8c8fbce613258658fb4f7b32d04c8d5d1d74a23c1e",
    "https://www.gay-torrents.net/torrentdetails.php?torrentid=061786bd69ef11cb258658fb4f7b32d0e5e79c24bc0f8574",
    "https://www.gay-torrents.net/torrentdetails.php?torrentid=580a28b3e3502970258658fb4f7b32d0b0551a006d092de8",
    "https://www.gay-torrents.net/torrentdetails.php?torrentid=8bb038ec9b0b388a258658fb4f7b32d01eab2c36706d34e8",
    "https://www.gay-torrents.net/torrentdetails.php?torrentid=f987a4b13deb1612258658fb4f7b32d05d5dcc48f7d5647e",
    "https://www.gay-torrents.net/torrentdetails.php?torrentid=a25c947537f52431258658fb4f7b32d0f3662f3b4c62d123",
    "https://www.gay-torrents.net/torrentdetails.php?torrentid=4483e0853bac781e258658fb4f7b32d01672f474c5f22dfd",
    "https://www.gay-torrents.net/torrentdetails.php?torrentid=70623f3048b770e2258658fb4f7b32d0381ae29af9b133d4",
    "https://www.gay-torrents.net/torrentdetails.php?torrentid=d5812881af074215258658fb4f7b32d0b8a6b5f0e474841a",
    "https://www.gay-torrents.net/torrentdetails.php?torrentid=ced10991e26bd571258658fb4f7b32d07c57601d5b1f9b6f",
    "https://www.gay-torrents.net/torrentdetails.php?torrentid=c63b265c9af428d5258658fb4f7b32d03fd0b516946b7c9e",
    "https://www.gay-torrents.net/torrentdetails.php?torrentid=00f8af32a74fa9a3258658fb4f7b32d0bf6faa736800851a",
    "https://www.gay-torrents.net/torrentdetails.php?torrentid=03907fda0dc680c6258658fb4f7b32d05437c9cec9e920e5",
    "https://www.gay-torrents.net/torrentdetails.php?torrentid=eef35ceeae0ab9ca258658fb4f7b32d021870b61e27599e9",
    "https://www.gay-torrents.net/torrentdetails.php?torrentid=67d5b2d6c7bd642d258658fb4f7b32d0318f65b9eff5cb77",
    "https://www.gay-torrents.net/torrentdetails.php?torrentid=3b6b83261ccafcf3258658fb4f7b32d095337103fe4ec55d",
    "https://www.gay-torrents.net/torrentdetails.php?torrentid=0d18d7a9262616cc258658fb4f7b32d0dec55ee2726e74ff",
    "https://www.gay-torrents.net/torrentdetails.php?torrentid=2c983db5dda0449c258658fb4f7b32d0a3b4edce6b077427",
    "https://www.gay-torrents.net/torrentdetails.php?torrentid=c1dd320fe6caf21d258658fb4f7b32d0c63cd517b1078625",
    "https://www.gay-torrents.net/torrentdetails.php?torrentid=f7db4d01f2668405258658fb4f7b32d0954bce0d1b5103e4",
    "https://www.gay-torrents.net/torrentdetails.php?torrentid=8b982db38807b4cd258658fb4f7b32d03ffb9d86b4135a08"
]

# If the input is mixed text (e.g., "torrentid=...") you can convert to full URLs:
def normalize_lines(lines):
    out = []
    for s in lines:
        s = s.strip()
        if not s:
            continue
        if s.startswith("torrentid="):
            tid = s.split("=", 1)[1].strip()
            out.append(f"https://www.gay-torrents.net/torrentdetails.php?torrentid={tid}")
        else:
            out.append(s)
    return out

URLS = normalize_lines(URLS)

# ---- SELECTORS ----
# The button lives under .vbfour-box > .body_wrapper > .postdetails > .userinfo
# CSS selector is written to be explicit and robust.
BUTTON_SELECTOR = ".vbfour-box .body_wrapper .postdetails .userinfo input[type='submit'][name='download'][value='as Torrent']"

def safe_filename_from_url(url: str) -> str:
    # Attempt to make a unique, short filename from the url
    p = urlparse(url)
    name = p.query or p.path or p.netloc
    # replace problematic chars
    safe = "".join(c if c.isalnum() else "_" for c in name)[:120]
    return safe or "download"

def main():
    with sync_playwright() as p:
        browser = p.chromium.launch(headless=HEADLESS)
        context = browser.new_context(accept_downloads=True)

        # set cookies if provided
        if COOKIES:
            context.add_cookies(COOKIES)

        page = context.new_page()

        for url in URLS:
            success = False
            for attempt in range(1, RETRY_COUNT + 2):
                try:
                    print(f"[{attempt}] Navigating to {url}")
                    page.goto(url, timeout=NAV_TIMEOUT_MS)
                    # Wait for the container rather than the button first (robustness)
                    page.wait_for_selector(".vbfour-box .body_wrapper .postdetails .userinfo", timeout=CLICK_TIMEOUT_MS)
                    # Wait for the button
                    btn = page.query_selector(BUTTON_SELECTOR)
                    if not btn:
                        # try a tolerant xpath in case of slightly different markup
                        btn = page.query_selector('//input[@type="submit" and @name="download" and contains(@value, "Torrent")]')
                    if not btn:
                        raise RuntimeError("Download button not found with expected selectors.")
                    # Trigger download and capture the Download object
                    with page.expect_download(timeout=30000) as download_info:
                        btn.click(timeout=5000)
                    download = download_info.value
                    suggested = download.suggested_filename or (safe_filename_from_url(url) + ".torrent")
                    target = DOWNLOAD_DIR / suggested
                    # If file exists, append numeric suffix
                    i = 1
                    base = target.stem
                    ext = target.suffix
                    while target.exists():
                        target = DOWNLOAD_DIR / f"{base}_{i}{ext}"
                        i += 1
                    download.save_as(str(target))
                    print(f"Saved {url} -> {target.name}")
                    success = True
                    break
                except PWTimeout as te:
                    print(f"Timeout on {url}: {te}. Attempt {attempt}")
                except Exception as e:
                    print(f"Error on {url}: {e}. Attempt {attempt}")
                time.sleep(1 + attempt * 0.5)
            if not success:
                print(f"Failed to download from {url} after {RETRY_COUNT+1} attempts.")
            time.sleep(REQUEST_DELAY)

        context.close()
        browser.close()
        print("Done.")

if __name__ == "__main__":
    main()
