#!/usr/bin/env bash
set -euo pipefail

# ==============================
# PATH INPUTS
# ==============================
INPUT_VIDEO="/Users/daniellarge/Movies/.DPLTORRCOMPLETE/2 MKV clips 251104/inputs/input2.mkv"             # main source video to cut from
INPUT_PNG="/Users/daniellarge/Movies/.DPLTORRCOMPLETE/2 MKV clips 251104/inputs/input2.png"                # still image used for the mid/tail still segment
INPUT_SUB_ENG="/Users/daniellarge/Movies/.DPLTORRCOMPLETE/2 MKV clips 251104/inputs/input2ESDH.srt"       # English SDH SRT (raw)
INPUT_SUB_DEU="/Users/daniellarge/Movies/.DPLTORRCOMPLETE/2 MKV clips 251104/inputs/input2D.srt"          # German SRT (raw)
CLOSING_MP4="/Users/daniellarge/Movies/.DPLTORRCOMPLETE/2 MKV clips 251104/inputs/offsequence2.mp4"       # optional closing clip (1080p, 25 fps)
OUT_DIR="/Users/daniellarge/Movies/.DPLTORRCOMPLETE/2 MKV clips 251104/inputs"                            # output directory for intermediates and final MP4

# ==============================
# TIMING MODEL
# ==============================
CONTENT_START=731          # second in INPUT_VIDEO where visible content begins
CONTENT_DURATION=745         # length of visible content (seconds), excludes fades
FADE_SEC=2.5                # fade duration (seconds) for in and out; fades sit OUTSIDE visible content
SUB_GUARD=0.3               # extra buffer to keep subs away from fade edges (defeats renderer rounding)
PNG_STILL_SEC=10            # <<< HOW LONG to show the still PNG (seconds). Set this.

# ==============================
# OPTIONS
# ==============================
APPEND_CLOSING=true         # set to "true" to append CLOSING_MP4 after the PNG still; "false" to disable

# ==============================
# DERIVED TIMINGS (no need to edit)
# ==============================
MAIN_START=$(awk -v c=$CONTENT_START -v f=$FADE_SEC 'BEGIN{printf("%.3f", c-f)}')                        # trim start in source
MAIN_END=$(awk -v c=$CONTENT_START -v d=$CONTENT_DURATION -v f=$FADE_SEC 'BEGIN{printf("%.3f", c+d+f)}') # trim end in source
FADE_OUT_START=$(awk -v d=$CONTENT_DURATION -v f=$FADE_SEC 'BEGIN{printf("%.3f", d+f)}')                 # fade-out start in output timeline
SUB_WIN_START=$(awk -v f=$FADE_SEC -v g=$SUB_GUARD 'BEGIN{printf("%.3f", f+g)}')                          # first subtitle time in output timeline
SUB_WIN_END=$(awk -v d=$CONTENT_DURATION -v f=$FADE_SEC -v g=$SUB_GUARD 'BEGIN{printf("%.3f", f+d-g)}')  # last subtitle time in output timeline
SHIFT_TO_OUTPUT=$(awk -v s=$MAIN_START 'BEGIN{printf("%.3f", -s)}')                                       # shift so t=0 at MAIN_START

# ==============================
# OUTPUT FILENAMES
# ==============================
SUB_ENG_CLEAN="$OUT_DIR/input2ESDH_visible.srt"    # rewritten English SDH SRT aligned to output timeline window (no fades)
SUB_DEU_CLEAN="$OUT_DIR/input2D_visible.srt"       # rewritten German SRT aligned to output timeline window (no fades)
OUTPUT_MP4="$OUT_DIR/output2.mp4"                  # final MP4

mkdir -p "$OUT_DIR"

# ==============================
# STEP 1 — REWRITE SUBTITLES TO THE OUTPUT TIMELINE (NO FADES)
# - Shift so 0 is MAIN_START.
# - Clamp to [SUB_WIN_START, SUB_WIN_END).
# - Drop cues outside; renumber cues.
# ==============================
python3 - "$INPUT_SUB_ENG" "$SUB_ENG_CLEAN" "$SHIFT_TO_OUTPUT" "$SUB_WIN_START" "$SUB_WIN_END" <<'PY'
import sys,re
src,dst,shift_s,win_start,win_end=sys.argv[1],sys.argv[2],float(sys.argv[3]),float(sys.argv[4]),float(sys.argv[5])
def parse_ts(s):
    h,m,rest=s.split(':'); s2,ms=rest.split(',')
    return int(h)*3600+int(m)*60+int(s2)+int(ms)/1000.0
def fmt_ts(t):
    if t<0: t=0
    h=int(t//3600); t-=h*3600
    m=int(t//60);   t-=m*60
    s=int(t);       ms=int(round((t-s)*1000))
    return f"{h:02d}:{m:02d}:{s:02d},{ms:03d}"
with open(src,'r',encoding='utf-8-sig') as f: raw=f.read()
blocks=re.split(r'\r?\n\r?\n',raw.strip(),flags=re.M)
out=[]; idx=1
for b in blocks:
    lines=b.strip().splitlines()
    if not lines: continue
    tline=None
    for i,L in enumerate(lines):
        if '-->' in L: tline=i; break
    if tline is None: continue
    t1s,t2s=map(str.strip,lines[tline].split('-->'))
    t1=parse_ts(t1s)+shift_s; t2=parse_ts(t2s)+shift_s
    if t2<=win_start or t1>=win_end: continue
    t1=max(t1,win_start); t2=min(t2,win_end)
    if t2<=t1: continue
    payload=lines[tline+1:]
    out.append(f"{idx}\n{fmt_ts(t1)} --> {fmt_ts(t2)}\n"+"\n".join(payload))
    idx+=1
with open(dst,'w',encoding='utf-8') as f:
    f.write("\n\n".join(out)+("\n" if out else ""))
PY

python3 - "$INPUT_SUB_DEU" "$SUB_DEU_CLEAN" "$SHIFT_TO_OUTPUT" "$SUB_WIN_START" "$SUB_WIN_END" <<'PY'
import sys,re
src,dst,shift_s,win_start,win_end=sys.argv[1],sys.argv[2],float(sys.argv[3]),float(sys.argv[4]),float(sys.argv[5])
def parse_ts(s):
    h,m,rest=s.split(':'); s2,ms=rest.split(',')
    return int(h)*3600+int(m)*60+int(s2)+int(ms)/1000.0
def fmt_ts(t):
    if t<0: t=0
    h=int(t//3600); t-=h*3600
    m=int(t//60);   t-=m*60
    s=int(t);       ms=int(round((t-s)*1000))
    return f"{h:02d}:{m:02d}:{s:02d},{ms:03d}"
with open(src,'r',encoding='utf-8-sig') as f: raw=f.read()
blocks=re.split(r'\r?\n\r?\n',raw.strip(),flags=re.M)
out=[]; idx=1
for b in blocks:
    lines=b.strip().splitlines()
    if not lines: continue
    tline=None
    for i,L in enumerate(lines):
        if '-->' in L: tline=i; break
    if tline is None: continue
    t1s,t2s=map(str.strip,lines[tline].split('-->'))
    t1=parse_ts(t1s)+shift_s; t2=parse_ts(t2s)+shift_s
    if t2<=win_start or t1>=win_end: continue
    t1=max(t1,win_start); t2=min(t2,win_end)
    if t2<=t1: continue
    payload=lines[tline+1:]
    out.append(f"{idx}\n{fmt_ts(t1)} --> {fmt_ts(t2)}\n"+"\n".join(payload))
    idx+=1
with open(dst,'w',encoding='utf-8') as f:
    f.write("\n\n".join(out)+("\n" if out else ""))
PY

# ==============================
# STEP 2 — DETECT CLOSING CLIP DURATION (OPTIONAL)
# - If APPEND_CLOSING=true and file exists with duration > 0, include it.
# - Otherwise, skip the closing segment.
# ==============================
CLOSING_DUR="0.0"
if $APPEND_CLOSING && [[ -f "$CLOSING_MP4" ]]; then
  CLOSING_DUR=$(ffprobe -v error -select_streams v:0 -show_entries format=duration -of csv=p=0 "$CLOSING_MP4" || echo "0")
  CLOSING_DUR=$(awk -v d="$CLOSING_DUR" 'BEGIN{if(d==""||d~"nan") d=0; printf("%.3f", d)}')
fi

# ==============================
# STEP 3 — ENCODE WITH FADES + STILL + OPTIONAL CLOSING
# - Segment A: main A/V with 2.5 s fades outside visible window.
# - Segment B: PNG still held for PNG_STILL_SEC with silent 5.1.
# - Segment C: closing clip normalized to 1080p/25 yuv420p with silent 5.1 (if needed).
# - Subtitles: soft, trimmed to visible window only, English SDH default+forced.
# ==============================
if $APPEND_CLOSING && awk -v d="$CLOSING_DUR" 'BEGIN{exit !(d>0)}'; then
  # 3-segment concat: main + still + closing
  ffmpeg -y -loglevel error -stats \
    -i "$INPUT_VIDEO" \
    -loop 1 -t "$PNG_STILL_SEC" -i "$INPUT_PNG" \
    -f lavfi -t "$PNG_STILL_SEC" -i "anullsrc=channel_layout=5.1:sample_rate=48000" \
    -i "$SUB_ENG_CLEAN" \
    -i "$SUB_DEU_CLEAN" \
    -i "$CLOSING_MP4" \
    -f lavfi -t "$CLOSING_DUR" -i "anullsrc=channel_layout=5.1:sample_rate=48000" \
    -filter_complex "
      [0:v]trim=start=${MAIN_START}:end=${MAIN_END},setpts=PTS-STARTPTS,
           scale=1920:-2,pad=1920:1080:(ow-iw)/2:(oh-ih)/2,setsar=1,fps=25,format=yuv420p,
           fade=t=in:st=0:d=${FADE_SEC},fade=t=out:st=${FADE_OUT_START}:d=${FADE_SEC}[vA];
      [0:a]atrim=start=${MAIN_START}:end=${MAIN_END},asetpts=PTS-STARTPTS,
           aresample=osr=48000:ocl=5.1,
           afade=t=in:st=0:d=${FADE_SEC},afade=t=out:st=${FADE_OUT_START}:d=${FADE_SEC}[aA];

      [1:v]setpts=PTS-STARTPTS,scale=1920:1080,setsar=1,fps=25,format=yuv420p[vB];
      [2:a]asetpts=PTS-STARTPTS,aresample=osr=48000:ocl=5.1[aB];

      [5:v]setpts=PTS-STARTPTS,scale=1920:1080,setsar=1,fps=25,format=yuv420p[vC];
      [6:a]asetpts=PTS-STARTPTS,aresample=osr=48000:ocl=5.1[aC];

      [vA][aA][vB][aB][vC][aC]concat=n=3:v=1:a=1[v][a]
    " \
    -map "[v]" -map "[a]" \
    -map 3 -map 4 -c:s mov_text \
    -disposition:s:0 default+forced -disposition:s:1 0 \
    -metadata:s:s:0 language=eng -metadata:s:s:0 title="English SDH" \
    -metadata:s:s:1 language=deu  -metadata:s:s:1 title="Deutsch" \
    -c:v libx264 -preset slow -crf 18 -pix_fmt yuv420p \
    -g 50 -sc_threshold 0 -force_key_frames "expr:gte(t,n_forced*2)" \
    -c:a eac3 -b:a 768k \
    -movflags +faststart -avoid_negative_ts make_zero -fflags +genpts \
    "$OUTPUT_MP4"
else
  # 2-segment concat: main + still
  ffmpeg -y -loglevel error -stats \
    -i "$INPUT_VIDEO" \
    -loop 1 -t "$PNG_STILL_SEC" -i "$INPUT_PNG" \
    -f lavfi -t "$PNG_STILL_SEC" -i "anullsrc=channel_layout=5.1:sample_rate=48000" \
    -i "$SUB_ENG_CLEAN" \
    -i "$SUB_DEU_CLEAN" \
    -filter_complex "
      [0:v]trim=start=${MAIN_START}:end=${MAIN_END},setpts=PTS-STARTPTS,
           scale=1920:-2,pad=1920:1080:(ow-iw)/2:(oh-ih)/2,setsar=1,fps=25,format=yuv420p,
           fade=t=in:st=0:d=${FADE_SEC},fade=t=out:st=${FADE_OUT_START}:d=${FADE_SEC}[vA];
      [0:a]atrim=start=${MAIN_START}:end=${MAIN_END},asetpts=PTS-STARTPTS,
           aresample=osr=48000:ocl=5.1,
           afade=t=in:st=0:d=${FADE_SEC},afade=t=out:st=${FADE_OUT_START}:d=${FADE_SEC}[aA];

      [1:v]setpts=PTS-STARTPTS,scale=1920:1080,setsar=1,fps=25,format=yuv420p[vB];
      [2:a]asetpts=PTS-STARTPTS,aresample=osr=48000:ocl=5.1[aB];

      [vA][aA][vB][aB]concat=n=2:v=1:a=1[v][a]
    " \
    -map "[v]" -map "[a]" \
    -map 3 -map 4 -c:s mov_text \
    -disposition:s:0 default+forced -disposition:s:1 0 \
    -metadata:s:s:0 language=eng -metadata:s:s:0 title="English SDH" \
    -metadata:s:s:1 language=deu  -metadata:s:s:1 title="Deutsch" \
    -c:v libx264 -preset slow -crf 18 -pix_fmt yuv420p \
    -g 50 -sc_threshold 0 -force_key_frames "expr:gte(t,n_forced*2)" \
    -c:a eac3 -b:a 768k \
    -movflags +faststart -avoid_negative_ts make_zero -fflags +genpts \
    "$OUTPUT_MP4"
fi

echo "Done → $OUTPUT_MP4"
echo "Subs → $SUB_ENG_CLEAN | $SUB_DEU_CLEAN"
