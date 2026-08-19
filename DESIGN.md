# No Focus Count Design System

## 1. Atmosphere & Identity

No Focus Count is a compact, dark desktop instrument that stays visually quiet until the user needs controls. Its signature is a luminous timer floating above restrained transparent glass, with lime as the single semantic accent for focus, selection, and live status.

## 2. Color

### Palette

| Role | Token | Value | Usage |
|---|---|---|---|
| Timer | `--timer` | `#D7FF5F` | Timer digits and focus emphasis |
| Accent | `--accent` | `#A7FF3F` | Active controls, progress, status |
| Panel | `--panel` | `#07100D` | Transparent dashboard and overlay glass |
| Text | `--text` | `rgba(255,255,255,.92)` | Primary copy |
| Muted | `--muted` | `rgba(255,255,255,.48)` | Labels and secondary copy |
| Line | `--line` | `rgba(255,255,255,.10)` | Quiet boundaries |
| Warning | legacy CSS | `#FFCE73` | Platform and focus warnings |
| Error | legacy CSS | `#FF8D8D` | Destructive actions |

### Rules

- The dark theme is locked across dashboard, overlay, and dialog surfaces.
- Lime remains the only general interaction accent. Warning and error colors are semantic exceptions.
- User-selected timer, accent, and panel colors update the corresponding tokens.
- Transparency never removes the underlying native transparent window. It changes rendered surface visibility through CSS so behavior is consistent across operating systems.
- The window switcher backdrop follows the configured surface opacity, while its interactive content keeps at least 82% opacity so controls and Korean helper text remain readable.

## 3. Typography

### Scale

| Level | Size | Weight | Usage |
|---|---:|---:|---|
| Timer/dashboard | `72-148px` | `520-620` | Primary countdown |
| Timer/overlay | `72px` | `620` | Floating countdown |
| Metric | `18px` | `650` | Session metrics |
| Section | `13-17px` | `650-750` | Dialog and compact section headings |
| Control | `10-13px` | `600-750` | Inputs and buttons |
| Caption | `8-10px` | `600-750` | Dense status metadata |

### Font Stack

- UI: system sans, currently `Inter, ui-sans-serif, -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif`.
- Status and metrics: platform monospace fallbacks.
- Display timer: a user-selectable, whitelisted family key resolved to platform-safe rounded, sans, mono, or serif stacks.

### Rules

- Timer digits use tabular numerals.
- The display font setting affects the dashboard timer, overlay timer, and theme preview together.
- Font family values are selected from known keys. Stored or imported arbitrary CSS is not accepted.

## 4. Spacing & Layout

### Base Unit

The intended base unit is 4px. Existing compact controls also use 5px, 7px, and 10px increments where density requires them.

| Token | Value | Usage |
|---|---:|---|
| `space-1` | `4px` | Tight icon and inline separation |
| `space-2` | `8px` | Compact groups |
| `space-3` | `12px` | Field padding |
| `space-4` | `16px` | Standard group spacing |
| `space-5` | `20px` | Compact shell padding |
| `space-6` | `24px` | Surface padding |
| `space-7` | `28px` | Dashboard content inset |

### Grid

- Dashboard: 900x780 default, 720x520 minimum.
- Shell: fixed title bar with `.content` as the only vertical scroll owner.
- Settings: three columns when wide, two columns below 780px.
- Overlay: fixed 336x136 surface with no scroll region.
- Theme fields may span two tracks but must collapse without horizontal overflow.

## 5. Components

### Dashboard Shell

- **Structure**: fixed draggable title bar plus scroll-body shell.
- **States**: transparent base, active tab, resizable compact-height layouts.
- **Accessibility**: controls remain in the normal keyboard order; draggable regions exclude inputs and buttons.
- **Layout**: `.content` owns scrolling and has a bounded height.

### Goal Todo Board

- **Structure**: compact heading and completion count, stepped focus-duration control, monitor picker, labeled goal form, then a bounded checklist.
- **States**: empty, active, completed, limit reached, keyboard focus.
- **Accessibility**: bounded numeric input, labeled stepper buttons, native select and checkbox semantics; every action has persistent Korean copy and visible focus.
- **Layout**: the board is the first content surface, uses two list columns when wide, and collapses to one column at the dashboard minimum width.
- **Interaction**: duration buttons adjust the next focus session in five-minute steps, the monitor picker scopes focus detection, and checklist actions add, complete, or remove goals; state feedback uses the existing `160ms` color/opacity micro token and becomes instant under reduced motion.

### Timer Display

- **Structure**: mode switch, timer number, phase status, hover actions.
- **Variants**: dashboard, theme preview, floating overlay.
- **States**: ready, focusing, paused, distracted, break, complete.
- **Accessibility**: tabular digits, persistent text status, user-selectable display family and overall visibility.
- **Motion**: hover actions use opacity and transform only.

### Settings Field

- **Structure**: visible label followed by input, select, or range and optional output.
- **Variants**: color, number, range, select, toggle.
- **States**: default, hover, focus-visible, checked, disabled.
- **Accessibility**: native labeled controls; outputs remain visible and update while dragging.
- **Layout**: field content can shrink; long labels do not force horizontal page scroll.

### Tab Strip

- **Structure**: navigation buttons mapped to one visible panel.
- **States**: default, hover, active, focus-visible.
- **Accessibility**: keyboard-reachable buttons; panel visibility is reflected with the existing active class.

### Window Switcher

- **Structure**: dialog header, monitor reel, window reel, action footer.
- **States**: empty, selected monitor, selected window, hover, focus.
- **Layout**: the monitor and window reels own horizontal scrolling.

## 6. Motion & Interaction

| Type | Duration | Easing | Usage |
|---|---:|---|---|
| Micro | `160-200ms` | `ease` | Hover controls and overlay affordances |
| Standard | `300ms` | `ease` | Goal progress |

- Motion communicates hover availability, selection, or changed progress only.
- Only opacity and transform are animated for controls. Goal width is an existing data visualization exception.
- Reduced-motion users receive instant state changes for nonessential transitions.
- Range inputs update the preview immediately and persist on change.
- Goal todos persist after add, complete, and delete actions; completion feedback follows the native checkbox mechanism with no decorative motion.

## 7. Depth & Surface

The strategy is mixed transparent glass: low-alpha panel color, backdrop blur, a quiet one-pixel rim, inset highlight, and restrained dark shadow. The dashboard is the deepest surface, the overlay reveals glass on interaction, and fields use lower-contrast nested surfaces. The app does not introduce additional card layers for the new appearance controls.

## 8. Accessibility Constraints & Accepted Debt

### Constraints

- Target WCAG 2.2 AA for newly changed controls.
- Every new control has a persistent text label and visible keyboard focus.
- Overall transparency is capped so the UI cannot be made fully invisible; the default preserves current appearance.
- Display font selection retains tabular numerals and a generic-family fallback on every supported OS.
- Settings survive keyboard use, narrow dashboard layouts, and 200 percent zoom through the existing scroll owner.
- Goal todo time, title, completion, and removal remain keyboard-operable and survive app restart, import/export, and configured device sync.

### Accepted Debt

| Item | Location | Why accepted | Owner / Exit |
|---|---|---|---|
| Existing 8-10px captions are below the preferred body-text floor | `cross-platform/src/styles.css` | Pre-existing dense desktop UI outside this targeted feature | Open; address in a dedicated accessibility pass |
| Existing CSS contains raw legacy colors and irregular spacing | `cross-platform/src/styles.css` | Extraction documents the current implementation without broad visual refactor | Open; consolidate when the theme system is next refactored |
| Several legacy buttons use text symbols instead of a unified icon family | `cross-platform/src/index.html` | Pre-existing control set outside this feature | Open; replace in a dedicated interaction cleanup |
