#!/usr/bin/env python3
"""Small, generated media fixtures; no personal media or network access."""
from pathlib import Path
import json, subprocess
root = Path(__file__).resolve().parents[1] / '.build/Fixtures'
root.mkdir(parents=True, exist_ok=True)
def ffmpeg(*args): subprocess.run(['ffmpeg', '-hide_banner', '-loglevel', 'error', '-y', *args], check=True)
ffmpeg('-f', 'lavfi', '-i', 'testsrc2=size=1280x720:rate=30', '-f', 'lavfi', '-i', 'sine=frequency=440:sample_rate=48000', '-t', '14', '-c:v', 'libx264', '-preset', 'ultrafast', '-crf', '24', '-pix_fmt', 'yuv420p', '-c:a', 'aac', str(root / 'Sample.mp4'))
(root / 'Sample.srt').write_text('1\n00:00:01,000 --> 00:00:06,000\nLiPlayer · Subtitle timing test\n\n2\n00:00:07,000 --> 00:00:12,000\nSecond subtitle · café · 中文\n')
(root / 'Styled.ass').write_text('''[Script Info]
ScriptType: v4.00+
PlayResX: 1280
PlayResY: 720
[V4+ Styles]
Format: Name, Fontname, Fontsize, PrimaryColour, SecondaryColour, OutlineColour, BackColour, Bold, Italic, Underline, StrikeOut, ScaleX, ScaleY, Spacing, Angle, BorderStyle, Outline, Shadow, Alignment, MarginL, MarginR, MarginV, Encoding
Style: Default,Arial,48,&H00FFFFFF,&H000000FF,&H00000000,&H80000000,0,0,0,0,100,100,0,0,1,2,1,2,30,30,35,1
[Events]
Format: Layer, Start, End, Style, Name, MarginL, MarginR, MarginV, Effect, Text
Dialogue: 0,0:00:01.00,0:00:12.00,Default,,0,0,0,,{\\b1}Styled ASS{\\b0} · café · 中文
''')
ffmpeg('-i', str(root / 'Sample.mp4'), '-f', 'lavfi', '-i', 'sine=frequency=880:sample_rate=48000', '-i', str(root / 'Styled.ass'), '-map', '0:v', '-map', '0:a', '-map', '1:a', '-map', '2', '-t', '14', '-c:v', 'copy', '-c:a', 'aac', '-c:s', 'ass', '-metadata:s:a:0', 'language=eng', '-metadata:s:a:1', 'language=jpn', str(root / 'Multi-track.mkv'))
ffmpeg('-f', 'lavfi', '-i', 'testsrc2=size=640x360:rate=24', '-t', '6', '-c:v', 'libvpx-vp9', '-deadline', 'realtime', '-cpu-used', '8', '-b:v', '450k', str(root / 'VP9.webm'))
ffmpeg('-f', 'lavfi', '-i', 'testsrc2=size=640x360:rate=24', '-t', '4', '-vf', 'format=yuv420p10le', '-c:v', 'libx265', '-preset', 'ultrafast', '-x265-params', 'log-level=error:pools=2:frame-threads=2:colorprim=9:transfer=16:colormatrix=9:hdr10=1', '-crf', '28', '-color_primaries', 'bt2020', '-color_trc', 'smpte2084', '-colorspace', 'bt2020nc', str(root / 'HDR10.mkv'))
ffmpeg('-f', 'lavfi', '-i', 'testsrc2=size=640x360:rate=24', '-t', '3', '-c:v', 'libsvtav1', '-preset', '12', '-svtav1-params', 'lp=2', '-crf', '40', str(root / 'AV1.webm'))
ffmpeg('-f', 'lavfi', '-i', 'sine=frequency=330:sample_rate=48000', '-t', '4', '-c:a', 'flac', str(root / 'Audio.flac'))
(root / 'Broken.mkv').write_bytes(b'This is intentionally not a Matroska file.\n')
hdr = json.loads(subprocess.check_output(['ffprobe', '-v', 'error', '-read_intervals', '%+#1', '-select_streams', 'v:0', '-show_frames', '-show_entries', 'frame=pix_fmt,color_space,color_primaries,color_transfer', '-of', 'json', str(root / 'HDR10.mkv')], text=True))['frames'][0]
assert hdr.get('color_transfer') == 'smpte2084' and hdr.get('color_primaries') == 'bt2020' and hdr.get('pix_fmt') == 'yuv420p10le', hdr
(root / 'Fixture-metadata.json').write_text(json.dumps({'hdr10': hdr}, indent=2) + '\n')
print(root)
