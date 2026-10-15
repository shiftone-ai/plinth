# 動画fixture

`video.mp4` は動画表示の試験用に生成した，音声なしの2秒のH.264動画．
外部サイトへの通信を使わず，WebKitのインライン再生と再接続後の再生を確認する．

生成コマンド:

```sh
ffmpeg -hide_banner -nostdin -f lavfi -i testsrc2=size=320x180:rate=12 \
  -t 2 -an -c:v libx264 -profile:v baseline -pix_fmt yuv420p -crf 32 \
  -movflags +faststart video.mp4
```
