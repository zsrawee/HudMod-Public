# HudMod Video Editor — AI Instructions

## Project Overview
- **Type**: Video editing software built with Godot 4 (GDScript + C#)
- **Location**: `D:\New folder\HUD\HudMod-Public`
- **Server**: HTTP server on `http://127.0.0.1:9876` for terminal control
- **API Client**: `D:\temp\api.js` (Node.js)

## How to Connect
1. User opens the project with F5 (Play mode)
2. Server starts automatically on port 9876
3. Send commands via: `node D:\temp\api.js D:\temp\req.json`
4. Request format: `{"cmd":"command_name","param1":"value1",...}`

## Available Commands (80+)

### Project Commands
- `project_new` — Create new project (params: name, dir, fps, width, height)
- `project_open` — Open project (params: dir)
- `project_save` — Save current project
- `project_save_as` — Save project to new location
- `project_info` — Get project information
- `project_settings` — Get/set project settings
- `project_state` — Get full project state as JSON

### Layer Commands
- `layer_list` — List all layers
- `layer_add` — Add new layer
- `layer_remove` — Remove layer (params: index)
- `layer_move` — Move layer (params: from, to)
- `layer_set` — Set layer properties (params: index, name, color, locked, hidden, mute, volume)
- `layer_duplicate` — Duplicate layer (params: index)

### Clip Commands
- `clip_add` — Add clip to layer (params: layer, frame, media, length)
- `clip_remove` — Remove clip (params: layer, frame)
- `clip_move` — Move clip (params: from_layer, from_frame, to_layer, to_frame)
- `clip_split` — Split clip (params: layer, frame)
- `clip_duplicate` — Duplicate clip (params: layer, frame)
- `clip_info` — Get clip details (params: layer, frame)
- `clip_list` — List all clips
- `clip_set` — Set clip properties (params: layer, frame, from, length)
- `clip_copy` / `clip_paste` — Copy/paste clips
- `clip_import` — Import video clip (params: path, layer, frame)
- `clip_trim` — Trim clip (params: layer, frame, side: 'left'/'right', amount)

### Text Commands
- `text_add` — Add text clip (params: text, layer, frame, length, font_size, color)
- `text_set` — Set text properties (params: layer, frame, text, font_size, color, outline_size, outline_color, shadow_size, shadow_color, horizontal_alignment)

### Component Commands
- `comp_list` — List components on clip (params: layer, frame)
- `comp_list_available` — List available components
- `comp_add` — Add component (params: layer, frame, section, type)
- `comp_remove` — Remove component (params: layer, frame, index)
- `comp_set` — Set component property (params: layer, frame, section, index, property, value)
- `comp_get` — Get component property (params: layer, frame, section, index)
- `comp_move` — Reorder component (params: layer, frame, section, from, to)
- `comp_enable` / `comp_disable` — Enable/disable component (params: layer, frame, index, section)

#### Component Sections
- `Display2D` — Display2D components (CanvasItem, Fade, Swing, Slide, Popup, etc.)
- `Image` — Image effects (Blur, Distortion, PostProcessing, Enhance, Artistic, Cinematic, Retro)
- `Color` — Color correction (HSL, WhiteBalance, Tone, LGG)
- `Text` — Text effects (Bounce, Flip, Pulse, Shake, Wave, Background, Gradient)
- `Sound` — Audio components

#### Component Categories
- `Image/Basic` — Invert, Mask, ChromaKey, Perspective
- `Image/Blur` — BlurGaussian, BlurLight, BlurMax, BlurMin, BlurMotion, BlurRay, BlurRotational
- `Image/Distortion` — DistBulge, DistHeat, DistLens, DistRipple, DistTwirl
- `Image/PostProcessing` — Glow, Rays, LensFlare, RadialChromaticAberration, DirectionalChromaticAberration
- `Image/Enhance` — Clarity, Denoise, Kawahara, Sharpen
- `Image/Artistic` — Emboss, Halftone, Hexagon, Pixelate, Posterize, Sketch, ToonEdge, Voronoi
- `Image/Cinematic` — Vignette, FilmGrain, Bars
- `Image/Retro` — Glitch, GlitchWeird, LEDGrid, VHS
- `Text/Animation` — TextBounce, TextFlip, TextPulse, TextShake, TextWave, TextWind
- `Text/Basic` — TextBackground
- `Text/Color` — TextGradient, TextRainbow
- `Text/Shape` — TextCurved, TextExtrude, TextMagnet
- `Display2D/InOutAnimation` — Fade, Swing, Slide, Popup
- `Color/ColorCorrection` — WhiteBalance, Tone, LGG
- `Color/ColorGrading` — HSL, HSLPerColor

### Clip Types
- `VideoClipRes` — Video clip
- `ImageClipRes` — Image clip
- `Text2DClipRes` — Text clip
- `AudioClipRes` — Audio clip
- `Camera2DClipRes` — Camera clip
- `AdjustmentClipRes` — Adjustment layer
- `Display2DClipRes` — Display2D base

### Animation Commands
- `keyframe_add` — Add keyframe (params: layer, frame, section, index, property, keyframe)
- `keyframe_remove` — Remove keyframe (params: layer, frame, section, index, property, keyframe)
- `keyframe_list` — List keyframes (params: layer, frame)

### Media Commands
- `media_list` — List registered media (params: filter: 'all'/'images'/'videos'/'audio')
- `media_register` — Register media file (params: path)
- `media_import` — Import media to project
- `media_remove` — Deregister media from cache

### Playback Commands
- `playback_play` — Start playback
- `playback_stop` — Stop playback
- `playback_seek` — Seek to frame (params: frame)
- `playback_set` — Set playback parameters (params: volume, replay)

### Timeline Commands
- `timeline_goto` — Stop playback and seek to frame (params: frame)
- `timeline_length` — Get or set timeline length (params: length)

### Time Marker Commands
- `timemarker_add` — Add time marker (params: frame, name, color, description)
- `timemarker_remove` — Remove time marker (params: frame)
- `timemarker_list` — List all time markers

### Render Commands
- `render_start` — Start rendering (params: output)
- `render_cancel` — Cancel rendering
- `render_settings` — Get/set render settings

### Viewport Commands
- `screenshot` — Capture current viewport as PNG
- `frame` — Seek to frame and capture screenshot as PNG (params: frame)

### File Operations
- `read` — Read file content (params: path)
- `write` — Write content to file (params: path, content)
- `edit` — Find and replace in file (params: path, find, replace)
- `ls` — List directory contents (params: path)

### Script Execution
- `eval` — Evaluate GDScript expression and return result (params: code)
- `exec` — Execute GDScript statements (params: code)
- `discover` — Read source code functions with comments (params: class)
- `inspect` — List methods/properties/signals of any autoload (params: class)
- `context` — Get full project context as readable text
- `capabilities` — Full feature map with all commands

### Collaborative Commands
- `snapshot` — Save project state snapshot (params: action: save/list/get, id)
- `diff` — Compare two snapshots (params: snapshot)
- `review` — Get collaborative review report
- `changes_log` — Get change history
- `changes_clear` — Clear change history

### Undo/Redo
- `undo` — Undo last action
- `redo` — Redo last undone action

### Editor Commands
- `editor_settings` — Get or set editor settings

### Audio Commands
- `transcribe` — Extract audio and convert speech to text (params: path, max_secs, model)

### Style Profile Commands
- `style_analyze` — Analyze project and create style profile (params: name)
- `style_list` — List saved profiles
- `style_info` — Get profile details (params: name)
- `style_delete` — Delete profile (params: name)
- `style_compare` — Compare two profiles (params: a, b)
- `style_apply` — Apply profile to project (params: name)

### Teaching Commands
- `style_teach_start` — Start teaching session (params: video)
- `style_teach_log` — Log a decision (params: action, details, reason)
- `style_teach_ask` — Ask user a question (params: question, context)
- `style_teach_answer` — Answer a question (params: question_id, answer)
- `style_teach_end` — End teaching session
- `style_sessions` — List teaching sessions
- `style_session_load` — Load a specific session (params: session)
- `style_practice` — Apply learned style to current project (params: name)
- `style_evaluate` — Evaluate AI's work (params: session or profile)

## Style Profiles

Style profiles are saved in `D:\New folder\HUD\HudMod-Public\profiles\`

### Profile Structure
```json
{
  "profile_name": "name",
  "created_at": "datetime",
  "summary": {
    "editing_style": "cinematic|retro|dreamy|energetic|informational|balanced",
    "complexity": "basic|intermediate|advanced",
    "has_text": true,
    "has_transitions": true,
    "pacing": "fast|moderate|slow"
  },
  "effects": {
    "frequency": {"CompVignette": 12, "CompHSL": 5},
    "top_effects": ["CompVignette", "CompFilmGrain"],
    "default_settings": {"CompVignette": {"opacity": 0.45}}
  },
  "text_style": {
    "most_used_size": 32,
    "has_outlines": true,
    "has_shadows": false
  },
  "color_grading": {
    "average_saturation": -0.1,
    "warmth": "cool"
  },
  "transitions": {
    "preferred": ["CompFade", "CompSlide"]
  },
  "timing": {
    "average_clip_duration": 90,
    "pacing": "moderate"
  }
}
```

## Teaching Workflow

### Phase 1: Guided Learning
1. User gives AI a video clip (e.g., vlog)
2. User "messes it up" or creates a "before" version
3. AI asks questions: "Where should I cut?", "What effects to add?"
4. AI logs every decision with reason
5. AI writes notes and questions for user

### Phase 2: Independent Practice
1. User gives AI a second clip without guidance
2. AI reads the style profile
3. AI applies the learned style
4. AI writes decision report with confidence levels

### Phase 3: Evaluation
1. Compare original teaching with practice results
2. Score accuracy of effects, cuts, timing
3. Provide feedback on what worked and what didn't

## AI Behavior Rules

1. **Always check if server is running** before sending commands
2. **Log every change** to track what was done
3. **Ask questions** when unsure about user's intent
4. **Write notes** about decisions and reasons
5. **Never use ffmpeg** — use Godot's built-in VideoDecoder
6. **Respect the style profile** when making edits
7. **Save frequently** — use project_save after major changes
8. **Report errors** clearly with context

## File Structure
```
HudMod-Public/
├── Autoload/
│   ├── HudModServer.gd      — HTTP server + ALL style commands (3000+ lines)
│   ├── MediaServer.gd       — Media handling
│   ├── MediaCache.gd        — Media registration
│   └── ProjectServer2.gd    — Project management
├── Build/
│   └── Res/
│       ├── MediaClipRes/    — Clip types
│       └── Component/       — Effects (70+)
├── Editor/
│   └── TimeLine/            — Timeline UI
├── profiles/                — Style profiles (JSON)
│   └── sessions/            — Teaching sessions (JSON)
└── AGENTS.md                — This file (read by AI on new sessions)
```

## How AI Reads This File
- opencode reads `AGENTS.md` automatically at the start of each new conversation
- All style profile logic is inside `HudModServer.gd` — no external style files needed
- Profiles are saved as JSON in `profiles/` directory
