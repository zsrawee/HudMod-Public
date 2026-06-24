$ffmpeg = "D:\New folder\HUD\HudMod-Public\addons\ffmpeg_codec\ffmpeg.exe"
$output = "D:\New folder\HUD\HudMod-Public\HudMod Video\generated_videos\creative_showcase_30s.mp4"
$filterFile = "$env:TEMP\filtergraph.txt"

$dur = "5.85"
# Build filtergraph content (hardcode 1 for fade duration since variable+colon breaks PS parsing)
$fg = @"
[0:v]drawtext=text='WELCOME':fontfile=fonts/ArialBold.ttf:fontcolor=0xFFD700:fontsize=72:x=(w-text_w)/2:y='if(lt(t\,0.5)\, -h+(h+h/2-150)*(t/0.5)\, h/2-150)',
drawtext=text='TO THIS MOMENT':fontfile=fonts/Arial.ttf:fontcolor=0xFFD700:fontsize=40:x=(w-text_w)/2:y='h/2+40':alpha='if(lt(t\,1)\, 0\, if(lt(t\,1.6)\, (t-1)/0.6\, 1))',
drawtext=text='★':fontfile=fonts/Arial.ttf:fontcolor=0xFFD700:fontsize=28:x=150:y=200:alpha='0.3+0.7*abs(sin(2*PI*3*t))',
drawtext=text='★':fontfile=fonts/Arial.ttf:fontcolor=0xFFD700:fontsize=18:x=900:y=300:alpha='0.3+0.7*abs(sin(2*PI*2.5*t+1))',
drawtext=text='✦':fontfile=fonts/Arial.ttf:fontcolor=0xFFA500:fontsize=22:x='550+200*sin(2*PI*0.5*t)':y='180+150*cos(2*PI*0.5*t)':alpha='0.4+0.6*abs(sin(2*PI*4*t))',
drawtext=text='●':fontfile=fonts/Arial.ttf:fontcolor=0xFFD700:fontsize=14:x=250:y=1000:alpha='0.2+0.8*abs(sin(2*PI*2*t+2))',
drawtext=text='★':fontfile=fonts/Arial.ttf:fontcolor=0xFFA500:fontsize=16:x=800:y=1500:alpha='0.3+0.7*abs(sin(2*PI*3.5*t+0.5))'[s1v];

[1:v]drawtext=text='EVERY':fontfile=fonts/ArialBold.ttf:fontcolor=0xFFFFFF:fontsize=72:x=(w-text_w)/2:y='h/2-200':alpha='if(lt(t\,0.8)\, t/0.8\, 1)',
drawtext=text='DREAM':fontfile=fonts/ArialBold.ttf:fontcolor=0xFFFFFF:fontsize=72:x=(w-text_w)/2:y='h/2+100':alpha='if(lt(t\,0.5)\, 0\, if(lt(t\,1.3)\, (t-0.5)/0.8\, 1))',
drawtext=text='●':fontfile=fonts/Arial.ttf:fontcolor=0x88CCFF:fontsize=20:x=200:y=500:alpha='0.5+0.5*abs(sin(2*PI*2*t))',
drawtext=text='●':fontfile=fonts/Arial.ttf:fontcolor=0x88CCFF:fontsize=14:x=850:y=1400:alpha='0.5+0.5*abs(sin(2*PI*3*t+1))',
drawtext=text='✦':fontfile=fonts/Arial.ttf:fontcolor=0xAADDFF:fontsize=18:x='400+300*sin(2*PI*0.3*t)':y='300+200*cos(2*PI*0.3*t)':alpha='0.3+0.7*abs(sin(2*PI*5*t))'[s2v];

[2:v]drawtext=text='STARTS WITH':fontfile=fonts/ArialBold.ttf:fontcolor=0xDDAAFF:fontsize='20+52*min(1\, t/1.5)':x=(w-text_w)/2:y='h/2-150',
drawtext=text='A STEP':fontfile=fonts/ArialBold.ttf:fontcolor=0xDDAAFF:fontsize='16+44*min(1\, (t-1)/1.2)':x=(w-text_w)/2:y='h/2+80':alpha='if(lt(t\,1)\, 0\, if(lt(t\,2.2)\, (t-1)/1.2\, 1))',
drawtext=text='✦':fontfile=fonts/Arial.ttf:fontcolor=0xCC88FF:fontsize=26:x='150+700*mod(t*0.2\,1)':y=300:alpha='0.4+0.6*abs(sin(2*PI*3*t))',
drawtext=text='✦':fontfile=fonts/Arial.ttf:fontcolor=0xCC88FF:fontsize=20:x='200+600*mod(t*0.15+0.5\,1)':y=1200:alpha='0.4+0.6*abs(sin(2*PI*4*t+2))',
drawtext=text='★':fontfile=fonts/Arial.ttf:fontcolor=0xDDAAFF:fontsize=14:x=800:y=1600:alpha='0.3+0.7*abs(sin(2*PI*2.5*t+1))'[s3v];

[3:v]drawtext=text='DONT WAIT':fontfile=fonts/ArialBold.ttf:fontcolor=0xFFFFFF:fontsize=64:x='(w-text_w)/2+10*sin(20*t)':y='h/2-100+5*sin(25*t)',
drawtext=text='ACT NOW':fontfile=fonts/ArialBold.ttf:fontcolor=0xFFFFFF:fontsize=56:x='(w-text_w)/2+8*sin(22*t+1)':y='h/2+60+4*sin(27*t+2)':alpha='if(lt(t\,0.3)\, t/0.3\, 1)',
drawtext=text='!':fontfile=fonts/ArialBold.ttf:fontcolor=0xFF6666:fontsize=72:x=850:y='h/2-150+6*sin(18*t)':alpha='0.5+0.5*abs(sin(2*PI*8*t))',
drawtext=text='!':fontfile=fonts/ArialBold.ttf:fontcolor=0xFF4444:fontsize=48:x=200:y='h/2+100+8*sin(15*t)':alpha='0.5+0.5*abs(sin(2*PI*6*t+1))',
drawtext=text='*':fontfile=fonts/Arial.ttf:fontcolor=0xFFFF00:fontsize=36:x=150:y=300:alpha='0.4+0.6*abs(sin(2*PI*5*t))'[s4v];

[4:v]drawtext=text='THE TIME':fontfile=fonts/ArialBold.ttf:fontcolor=0xAAFFAA:fontsize='55+15*sin(4*t)':x=(w-text_w)/2:y='h/2-120',
drawtext=text='IS NOW':fontfile=fonts/ArialBold.ttf:fontcolor=0xAAFFAA:fontsize='45+12*sin(4*t+PI)':x=(w-text_w)/2:y='h/2+80':alpha='if(lt(t\,0.5)\, 0\, if(lt(t\,1.5)\, (t-0.5)\, 1))',
drawtext=text='●':fontfile=fonts/Arial.ttf:fontcolor=0x66FF66:fontsize=18:x=300:y=600:alpha='0.5+0.5*sin(2*PI*3*t)',
drawtext=text='●':fontfile=fonts/Arial.ttf:fontcolor=0x66FF66:fontsize=14:x=700:y=1300:alpha='0.5+0.5*sin(2*PI*2*t+1)',
drawtext=text='●':fontfile=fonts/Arial.ttf:fontcolor=0x88FF88:fontsize=10:x=500:y=900:alpha='0.3+0.7*abs(sin(2*PI*4*t+0.5))'[s5v];

[5:v]drawtext=text='CREATED':fontfile=fonts/ArialBold.ttf:fontcolor=0xFFD700:fontsize=72:x=(w-text_w)/2:y='h/2-200':alpha='if(lt(t\,0.6)\, t/0.6\, 1)',
drawtext=text='WITH HUDMOD':fontfile=fonts/ArialBold.ttf:fontcolor=0xFFA500:fontsize=48:x=(w-text_w)/2:y='h/2+80':alpha='if(lt(t\,0.8)\, 0\, if(lt(t\,1.6)\, (t-0.8)/0.8\, 1))',
drawtext=text='★':fontfile=fonts/Arial.ttf:fontcolor=0xFFD700:fontsize=36:x=100:y=150:alpha='0.3+0.7*abs(sin(2*PI*3*t))',
drawtext=text='★':fontfile=fonts/Arial.ttf:fontcolor=0xFFD700:fontsize=28:x=950:y=250:alpha='0.3+0.7*abs(sin(2*PI*2*t+1))',
drawtext=text='★':fontfile=fonts/Arial.ttf:fontcolor=0xFFA500:fontsize=22:x=200:y=800:alpha='0.4+0.6*abs(sin(2*PI*4*t+0.5))',
drawtext=text='★':fontfile=fonts/Arial.ttf:fontcolor=0xFFD700:fontsize=32:x=750:y=1000:alpha='0.3+0.7*abs(sin(2*PI*3.5*t+1.5))',
drawtext=text='★':fontfile=fonts/Arial.ttf:fontcolor=0xFFA500:fontsize=18:x=500:y=500:alpha='0.5+0.5*abs(sin(2*PI*5*t+2))',
drawtext=text='✦':fontfile=fonts/Arial.ttf:fontcolor=0xFFD700:fontsize=24:x='300+400*sin(2*PI*0.4*t)':y='200+300*cos(2*PI*0.4*t)':alpha='0.4+0.6*abs(sin(2*PI*3*t))',
drawtext=text='✦':fontfile=fonts/Arial.ttf:fontcolor=0xFFA500:fontsize=20:x='600+300*sin(2*PI*0.3*t+1)':y='1400+200*cos(2*PI*0.3*t+1)':alpha='0.4+0.6*abs(sin(2*PI*4*t+1))',
drawtext=text='●':fontfile=fonts/Arial.ttf:fontcolor=0xFFD700:fontsize=16:x=400:y=1700:alpha='0.2+0.8*abs(sin(2*PI*2*t+3))'[s6v];

[s1v][s2v]xfade=transition=fade:duration=1:offset=4.85[t12v];
[t12v][s3v]xfade=transition=fade:duration=1:offset=9.70[t123v];
[t123v][s4v]xfade=transition=fade:duration=1:offset=14.55[t1234v];
[t1234v][s5v]xfade=transition=fade:duration=1:offset=19.40[t12345v];
[t12345v][s6v]xfade=transition=fade:duration=1:offset=24.25[tv];

[6:a]aresample=44100[a1];
[7:a]aresample=44100[a2];
[8:a]aresample=44100[a3];
[9:a]aresample=44100[a4];
[10:a]aresample=44100[a5];
[11:a]aresample=44100[a6];

[a1][a2]acrossfade=d=1[af12];
[af12][a3]acrossfade=d=1[af123];
[af123][a4]acrossfade=d=1[af1234];
[af1234][a5]acrossfade=d=1[af12345];
[af12345][a6]acrossfade=d=1[fa];
"@

Write-Host "Writing filtergraph to $filterFile..."
$fg | Set-Content -Path $filterFile -Encoding ASCII

# Read filtergraph content
$fgContent = Get-Content -Path $filterFile -Raw

Write-Host "Building 30-second video with FFmpeg..."
$argsArray = @(
    '-y',
    '-f', 'lavfi', '-i', "color=c=0x1a0a2e:s=1080x1920:d=${dur}",
    '-f', 'lavfi', '-i', "color=c=0x0a2e5c:s=1080x1920:d=${dur}",
    '-f', 'lavfi', '-i', "color=c=0x2e0a5c:s=1080x1920:d=${dur}",
    '-f', 'lavfi', '-i', "color=c=0x5c0a0a:s=1080x1920:d=${dur}",
    '-f', 'lavfi', '-i', "color=c=0x0a5c0a:s=1080x1920:d=${dur}",
    '-f', 'lavfi', '-i', "color=c=0x1a0a2e:s=1080x1920:d=${dur}",
    '-f', 'lavfi', '-i', "aevalsrc=sin(2*PI*80*t)+0.4*sin(2*PI*120*t)+0.2*sin(2*PI*55*t):d=${dur}:s=44100:c=stereo",
    '-f', 'lavfi', '-i', "aevalsrc=sin(2*PI*200*t)+0.3*sin(2*PI*260*t):d=${dur}:s=44100:c=stereo",
    '-f', 'lavfi', '-i', "aevalsrc=sin(2*PI*320*t)+0.3*sin(2*PI*380*t)+0.15*sin(2*PI*450*t):d=${dur}:s=44100:c=stereo",
    '-f', 'lavfi', '-i', "aevalsrc=sin(2*PI*440*t)+0.5*sin(2*PI*520*t)+0.25*sin(2*PI*660*t):d=${dur}:s=44100:c=stereo",
    '-f', 'lavfi', '-i', "aevalsrc=sin(2*PI*550*t)+0.3*sin(2*PI*660*t)+0.2*sin(2*PI*770*t):d=${dur}:s=44100:c=stereo",
    '-f', 'lavfi', '-i', "aevalsrc=sin(2*PI*700*t)+0.5*sin(2*PI*880*t)+0.3*sin(2*PI*1040*t)+0.15*sin(2*PI*1320*t):d=${dur}:s=44100:c=stereo",
    '-filter_complex', $fgContent,
    '-map', '[tv]',
    '-map', '[fa]',
    '-c:v', 'mpeg4',
    '-qscale:v', '5',
    '-c:a', 'aac',
    '-pix_fmt', 'yuv420p',
    $output
)

& $ffmpeg $argsArray 2>&1

if ($LASTEXITCODE -eq 0) {
    Write-Host "SUCCESS! Video created at: $output"
    $fi = Get-Item $output
    Write-Host ("File size: " + $fi.Length + " bytes (" + [math]::Round($fi.Length/1MB, 2) + " MB)")
} else {
    Write-Host "FAILED with exit code: $LASTEXITCODE"
}
