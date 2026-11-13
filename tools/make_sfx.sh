#!/bin/bash
# Skyjoust SFX: synthesized with ffmpeg (deterministic, no tonal pads in ambience). Output MP3 in game/assets/sfx.
set -e
cd "$(dirname "$0")/.."
O=game/assets/sfx; mkdir -p $O
F="ffmpeg -y -hide_banner -loglevel error"
# flap: short filtered-noise whoosh
$F -f lavfi -i "anoisesrc=d=0.22:c=pink:a=0.9" -af "afade=t=in:d=0.03,afade=t=out:st=0.08:d=0.14,highpass=f=300,lowpass=f=2200,volume=2" -ar 44100 -c:a libmp3lame -q:a 3 $O/flap.mp3
# dash: crisp air-lunge whoosh + bright harmonic sweep
$F -f lavfi -i "anoisesrc=d=0.26:c=white:a=0.7" -f lavfi -i "aevalsrc='0.28*sin(2*PI*(320+1100*t)*t)*exp(-7*t)':d=0.26" -filter_complex "[0]bandpass=f=1400:w=1600,afade=t=in:d=0.02,afade=t=out:st=0.08:d=0.18[n];[n][1]amix=2:normalize=0,volume=1.1" -ar 44100 -c:a libmp3lame -q:a 3 $O/dash.mp3
# clash (level lances): metallic ping = two inharmonic sines + noise tick
$F -f lavfi -i "sine=f=1870:d=0.35" -f lavfi -i "sine=f=2730:d=0.35" -f lavfi -i "anoisesrc=d=0.04:c=white:a=0.6" -filter_complex "[0][1]amix=2,afade=t=out:st=0.02:d=0.33[a];[2]highpass=f=3000[n];[a][n]amix=2:normalize=0,volume=0.7" -ar 44100 -c:a libmp3lame -q:a 3 $O/clash.mp3
# kill: thump + rising chime
$F -f lavfi -i "sine=f=90:d=0.25" -f lavfi -i "aevalsrc='0.35*sin(2*PI*(660+900*t)*t)*exp(-6*t)':d=0.5" -filter_complex "[0]afade=t=out:st=0.0:d=0.25,volume=1.8[a];[a][1]amix=2:normalize=0" -ar 44100 -c:a libmp3lame -q:a 3 $O/kill.mp3
# egg collect: bright two-note pop
$F -f lavfi -i "aevalsrc='0.4*sin(2*PI*1046*t)*exp(-14*t)*lt(t,0.09)+0.4*sin(2*PI*1568*(t-0.08))*exp(-10*(t-0.08))*gte(t,0.08)':d=0.4" -ar 44100 -c:a libmp3lame -q:a 3 $O/egg.mp3
# hatch: crack (noise burst) + squawk-ish chirp
$F -f lavfi -i "anoisesrc=d=0.08:c=white:a=0.8" -f lavfi -i "aevalsrc='0.3*sin(2*PI*(1200-600*t)*t)*exp(-5*t)':d=0.35" -filter_complex "[0]bandpass=f=2500:w=2000[n];[n][1]concat=n=2:v=0:a=1" -ar 44100 -c:a libmp3lame -q:a 3 $O/hatch.mp3
# death: falling tone + low noise
$F -f lavfi -i "aevalsrc='0.45*sin(2*PI*(520-380*t)*t)*exp(-2.2*t)':d=0.9" -f lavfi -i "anoisesrc=d=0.6:c=brown:a=0.7" -filter_complex "[1]lowpass=f=400,afade=t=out:st=0.1:d=0.5[n];[0][n]amix=2:normalize=0" -ar 44100 -c:a libmp3lame -q:a 3 $O/death.mp3
# lava splash/sizzle
$F -f lavfi -i "anoisesrc=d=0.7:c=pink:a=0.9" -af "highpass=f=1500,afade=t=in:d=0.02,afade=t=out:st=0.1:d=0.6,volume=1.3" -ar 44100 -c:a libmp3lame -q:a 3 $O/sizzle.mp3
# pterodactyl screech: harsh FM sweep
$F -f lavfi -i "aevalsrc='0.35*sin(2*PI*(900+400*sin(2*PI*30*t))*t+3*sin(2*PI*55*t))*(1-exp(-30*t))*exp(-2.5*t)':d=0.8" -ar 44100 -c:a libmp3lame -q:a 3 $O/screech.mp3
# wave start: three-note rising fanfare
$F -f lavfi -i "aevalsrc='0.3*(sin(2*PI*523*t)*lt(t,0.14)+sin(2*PI*659*t)*gte(t,0.14)*lt(t,0.28)+sin(2*PI*784*t)*gte(t,0.28))*exp(-1.5*t)':d=0.9" -ar 44100 -c:a libmp3lame -q:a 3 $O/wave.mp3
# extra life
$F -f lavfi -i "aevalsrc='0.3*sin(2*PI*(880+440*floor(t*12)/6)*t)*exp(-2*t)':d=0.6" -ar 44100 -c:a libmp3lame -q:a 3 $O/life.mp3
# ambience: low lava rumble + soft wind, brown/pink noise only (no tonal content), seamless crossfaded 20 s loop
$F -f lavfi -i "anoisesrc=d=22:c=brown:a=0.6" -f lavfi -i "anoisesrc=d=22:c=pink:a=0.25" -filter_complex "[0]lowpass=f=180,volume='0.8+0.2*sin(2*PI*t/10)':eval=frame[r];[1]bandpass=f=600:w=500,volume='0.5+0.5*sin(2*PI*t/20)':eval=frame[w];[r][w]amix=2:normalize=0,asplit=2[x][y];[x]atrim=0:11,asetpts=N/SR/TB[a];[y]atrim=10:21,asetpts=N/SR/TB[b];[b][a]acrossfade=d=2:c1=tri:c2=tri" -ar 44100 -c:a libmp3lame -q:a 3 $O/ambience.mp3
ls -la $O
