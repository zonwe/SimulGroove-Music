"""Generate platform launcher icons from the repository's master icon."""

from pathlib import Path

from PIL import Image


ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / "assets" / "branding" / "app_icon.png"


def write_png(image: Image.Image, relative_path: str, size: int) -> None:
    destination = ROOT / relative_path
    destination.parent.mkdir(parents=True, exist_ok=True)
    resized = image.resize((size, size), Image.Resampling.LANCZOS)
    resized.save(destination, format="PNG", optimize=True)


def main() -> None:
    with Image.open(SOURCE) as source:
        icon = source.convert("RGB")

        png_targets = {
            # Android legacy launcher icons.
            "android/app/src/main/res/mipmap-mdpi/ic_launcher.png": 48,
            "android/app/src/main/res/mipmap-hdpi/ic_launcher.png": 72,
            "android/app/src/main/res/mipmap-xhdpi/ic_launcher.png": 96,
            "android/app/src/main/res/mipmap-xxhdpi/ic_launcher.png": 144,
            "android/app/src/main/res/mipmap-xxxhdpi/ic_launcher.png": 192,
            # Web and PWA icons.
            "web/favicon.png": 32,
            "web/icons/Icon-192.png": 192,
            "web/icons/Icon-512.png": 512,
            "web/icons/Icon-maskable-192.png": 192,
            "web/icons/Icon-maskable-512.png": 512,
            # iOS icon catalog.
            "ios/Runner/Assets.xcassets/AppIcon.appiconset/Icon-App-20x20@1x.png": 20,
            "ios/Runner/Assets.xcassets/AppIcon.appiconset/Icon-App-20x20@2x.png": 40,
            "ios/Runner/Assets.xcassets/AppIcon.appiconset/Icon-App-20x20@3x.png": 60,
            "ios/Runner/Assets.xcassets/AppIcon.appiconset/Icon-App-29x29@1x.png": 29,
            "ios/Runner/Assets.xcassets/AppIcon.appiconset/Icon-App-29x29@2x.png": 58,
            "ios/Runner/Assets.xcassets/AppIcon.appiconset/Icon-App-29x29@3x.png": 87,
            "ios/Runner/Assets.xcassets/AppIcon.appiconset/Icon-App-40x40@1x.png": 40,
            "ios/Runner/Assets.xcassets/AppIcon.appiconset/Icon-App-40x40@2x.png": 80,
            "ios/Runner/Assets.xcassets/AppIcon.appiconset/Icon-App-40x40@3x.png": 120,
            "ios/Runner/Assets.xcassets/AppIcon.appiconset/Icon-App-60x60@2x.png": 120,
            "ios/Runner/Assets.xcassets/AppIcon.appiconset/Icon-App-60x60@3x.png": 180,
            "ios/Runner/Assets.xcassets/AppIcon.appiconset/Icon-App-76x76@1x.png": 76,
            "ios/Runner/Assets.xcassets/AppIcon.appiconset/Icon-App-76x76@2x.png": 152,
            "ios/Runner/Assets.xcassets/AppIcon.appiconset/Icon-App-83.5x83.5@2x.png": 167,
            "ios/Runner/Assets.xcassets/AppIcon.appiconset/Icon-App-1024x1024@1x.png": 1024,
            # macOS icon catalog.
            "macos/Runner/Assets.xcassets/AppIcon.appiconset/app_icon_16.png": 16,
            "macos/Runner/Assets.xcassets/AppIcon.appiconset/app_icon_32.png": 32,
            "macos/Runner/Assets.xcassets/AppIcon.appiconset/app_icon_64.png": 64,
            "macos/Runner/Assets.xcassets/AppIcon.appiconset/app_icon_128.png": 128,
            "macos/Runner/Assets.xcassets/AppIcon.appiconset/app_icon_256.png": 256,
            "macos/Runner/Assets.xcassets/AppIcon.appiconset/app_icon_512.png": 512,
            "macos/Runner/Assets.xcassets/AppIcon.appiconset/app_icon_1024.png": 1024,
        }

        for path, size in png_targets.items():
            write_png(icon, path, size)

        windows_icon = ROOT / "windows" / "runner" / "resources" / "app_icon.ico"
        windows_icon.parent.mkdir(parents=True, exist_ok=True)
        icon.save(
            windows_icon,
            format="ICO",
            sizes=[
                (16, 16),
                (24, 24),
                (32, 32),
                (48, 48),
                (64, 64),
                (128, 128),
                (256, 256),
            ],
        )


if __name__ == "__main__":
    main()
