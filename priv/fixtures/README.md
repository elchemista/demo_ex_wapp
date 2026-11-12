# Messaging fixtures

The suite sends these small, local files only when started from the dashboard.
MP4 and WebP fixtures are synthetic FFmpeg patterns without external assets or
personal content. FFmpeg is needed only to regenerate them, not to run the demo
or ExUnit tests.

Run from the repository root:

```bash
ffmpeg -y -f lavfi -i 'testsrc2=size=128x128:rate=10' -t 1 \
  -c:v libx264 -pix_fmt yuv420p -movflags +faststart priv/fixtures/test-video.mp4

ffmpeg -y -f lavfi -i 'color=c=green:s=512x512' -frames:v 1 \
  -c:v libwebp priv/fixtures/test-sticker.webp

ffmpeg -y -f lavfi -i 'testsrc2=size=512x512:rate=5' -t 1 \
  -c:v libwebp_anim -quality 50 -loop 0 priv/fixtures/test-animated-sticker.webp
```

The same one-second MP4 is used for normal video and `gif_playback: true`.
Static and animated stickers use distinct 512×512 WebP files. The suite supplies
dimensions and duration explicitly because ExWapp does not inspect or transcode
media. Existing image, audio, and document fixtures retain their original uses.
