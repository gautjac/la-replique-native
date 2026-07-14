# tools/make-icon.swift

Renders the master 1024 app icon (charcoal desk + gel/teal guillemets « »).
Regenerate the icon set:

```sh
swift tools/make-icon.swift /tmp/appicon.png
for px in 16 32 64 128 256 512 1024; do
  sips -z $px $px /tmp/appicon.png --out Sources/Resources/Assets.xcassets/AppIcon.appiconset/icon-$px.png
done
```
