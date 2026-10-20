class_name UiTheme
extends RefCounted
## EVERAFTER — shared design system for the interface.
##
## The interface is deliberately *quiet*: it sits on top of a bright, hand-built
## 3D village and must never compete with it. Everything here follows four rules.
##
## 1. **One ink, one accent.** Panels are near-black warm ink (`INK_*`) with a
##    single hairline border; gold (`ACCENT*`) is reserved for the game name,
##    section overlines and the focused control. No chocolate-brown boxes with
##    double gold frames.
## 2. **Typography carries the hierarchy.** A serif display face is used only for
##    the title, names and numbers; body copy is a humanist sans at 13 px; section
##    labels are 10 px uppercase with wide tracking, never coloured blocks.
## 3. **An 8-point rhythm.** `GAP_*` constants keep every margin, padding and
##    separation on the same scale so panels line up instead of merely fitting.
## 4. **Zero binary assets.** Fonts are `SystemFont` stacks, shapes are
##    `StyleBoxFlat`, so the repository stays 100% text (see `docs/ARCHITECTURE.md`).
##
## `WorldHud`, `EconomyPanel`, `NpcPanel`, `SaveLoadPanel`, `DiagnosticsHud` and
## `WorldMap` all draw from this file, which is why they now read as one product.

# --- palette -----------------------------------------------------------------

## Panel and modal surfaces: warm near-black, never pure #000.
const BG_PANEL := Color(0.055, 0.052, 0.047, 0.94)
const BG_HUD := Color(0.055, 0.052, 0.047, 0.90)
const BG_MODAL := Color(0.043, 0.041, 0.037, 0.98)
const BG_INSET := Color(0.086, 0.080, 0.071, 0.96)
const BG_BADGE := Color(0.118, 0.109, 0.095, 0.96)
const BG_BAR_TRACK := Color(0.098, 0.092, 0.083, 1.0)

const BG_BUTTON := Color(0.102, 0.095, 0.084, 0.96)
const BG_BUTTON_HOVER := Color(0.153, 0.140, 0.120, 0.98)
const BG_BUTTON_PRESSED := Color(0.078, 0.073, 0.065, 0.98)
const BG_BUTTON_DISABLED := Color(0.086, 0.081, 0.074, 0.55)
const BG_BUTTON_ACTIVE := Color(0.196, 0.166, 0.106, 0.98)

## Hairlines. `BRASS` is the ordinary panel rim, `GOLD` the focused one.
const BORDER_BRASS := Color(0.85, 0.73, 0.50, 0.17)
const BORDER_GOLD_BRIGHT := Color(0.88, 0.75, 0.49, 0.62)
const BORDER_SUBTLE := Color(0.78, 0.72, 0.60, 0.10)

## Text.
const TEXT_GOLD := Color(0.898, 0.788, 0.573, 1.0)
const TEXT_GOLD_DIM := Color(0.686, 0.596, 0.427, 1.0)
const TEXT_PARCHMENT := Color(0.933, 0.914, 0.867, 1.0)
const TEXT_SECONDARY := Color(0.761, 0.741, 0.694, 1.0)
const TEXT_MUTED := Color(0.565, 0.549, 0.510, 1.0)

## Semantic accents: desaturated so six of them can coexist on screen.
const TEXT_GOOD := Color(0.604, 0.792, 0.573, 1.0)
const TEXT_WARN := Color(0.894, 0.722, 0.451, 1.0)
const TEXT_CRITICAL := Color(0.878, 0.545, 0.482, 1.0)
const TEXT_CALM := Color(0.620, 0.749, 0.859, 1.0)
const TEXT_LILAC := Color(0.788, 0.706, 0.851, 1.0)

# --- layout rhythm -----------------------------------------------------------

const GAP_XS := 4
const GAP_S := 8
const GAP_M := 12
const GAP_L := 16
const GAP_XL := 24

const SCREEN_MARGIN := 24.0
const LEFT_COLUMN_WIDTH := 312.0
const RIGHT_COLUMN_WIDTH := 344.0
## Top of the economy card: just below the fixed-height status card.
const LEFT_COLUMN_STACK_TOP := 184.0
const PANEL_RADIUS := 6

# --- typography --------------------------------------------------------------

static var _shared_theme: Theme = null
static var _header_font: Font = null
static var _body_font: Font = null
static var _overline_font: Font = null
static var _mono_font: Font = null


## Returns the singleton `Theme` applied to every root UI control.
static func shared_theme() -> Theme:
	if _shared_theme != null:
		return _shared_theme
	var theme := Theme.new()
	theme.default_font = body_font()
	theme.default_font_size = 13
	_configure_labels(theme)
	_configure_buttons(theme)
	_configure_popups(theme)
	_configure_tooltips(theme)
	_configure_separators(theme)
	_configure_fields_and_bars(theme)
	_configure_scrollbars(theme)
	_shared_theme = theme
	return _shared_theme


## Serif display face: titles, inhabitant names and the large numbers.
static func header_font() -> Font:
	if _header_font != null:
		return _header_font
	var sys := SystemFont.new()
	sys.font_names = PackedStringArray([
		"Constantia",
		"Palatino Linotype",
		"Book Antiqua",
		"Georgia",
		"Noto Serif",
		"DejaVu Serif",
	])
	sys.antialiasing = TextServer.FONT_ANTIALIASING_GRAY
	var variation := FontVariation.new()
	variation.base_font = sys
	# A touch of embolden: enough presence at 20 px, no smeared fake-bold.
	variation.variation_embolden = 0.06
	variation.spacing_glyph = 0
	_header_font = variation
	return _header_font


## Humanist sans for body copy, tables, buttons and logs.
static func body_font() -> Font:
	if _body_font != null:
		return _body_font
	var sys := SystemFont.new()
	sys.font_names = PackedStringArray([
		"Segoe UI",
		"Candara",
		"Inter",
		"Helvetica Neue",
		"Noto Sans",
		"DejaVu Sans",
	])
	sys.antialiasing = TextServer.FONT_ANTIALIASING_GRAY
	_body_font = sys
	return _body_font


## Wide-tracked sans used for 10 px uppercase section overlines.
static func overline_font() -> Font:
	if _overline_font != null:
		return _overline_font
	var variation := FontVariation.new()
	variation.base_font = body_font()
	variation.spacing_glyph = 2
	_overline_font = variation
	return _overline_font


## Tabular monospace for the diagnostics overlay.
static func mono_font() -> Font:
	if _mono_font != null:
		return _mono_font
	var sys := SystemFont.new()
	sys.font_names = PackedStringArray([
		"Cascadia Mono",
		"Consolas",
		"SF Mono",
		"DejaVu Sans Mono",
	])
	sys.antialiasing = TextServer.FONT_ANTIALIASING_GRAY
	_mono_font = sys
	return _mono_font


# --- semantic label styles ---------------------------------------------------


## Large serif label: the game name, an inhabitant's name, a headline number.
static func style_title_label(
	label: Label, font_size: int = 18, color: Color = TEXT_PARCHMENT
) -> void:
	if label == null:
		return
	label.add_theme_font_override("font", header_font())
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)


## 10 px uppercase, wide-tracked overline (`ECONOMIA`, `BISOGNI`, `LEGAMI`).
static func style_section_label(label: Label, font_size: int = 10) -> void:
	if label == null:
		return
	label.add_theme_font_override("font", overline_font())
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", TEXT_GOLD_DIM)


## Secondary overline used above values in the HUD (`GIORNO`, `AREA`).
static func style_overline_label(label: Label, color: Color = TEXT_MUTED) -> void:
	if label == null:
		return
	label.add_theme_font_override("font", overline_font())
	label.add_theme_font_size_override("font_size", 10)
	label.add_theme_color_override("font_color", color)


## Body copy with a consistent size/colour pair.
static func style_body_label(
	label: Label, font_size: int = 13, color: Color = TEXT_SECONDARY
) -> void:
	if label == null:
		return
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)


## Small monospaced-ish key hint (`P`, `C`, `+/-`).
static func style_keycap(label: Label) -> void:
	if label == null:
		return
	label.add_theme_font_override("font", body_font())
	label.add_theme_font_size_override("font_size", 11)
	label.add_theme_color_override("font_color", TEXT_PARCHMENT)
	label.add_theme_stylebox_override(
		"normal", make_inset_style(BG_BADGE, BORDER_SUBTLE, 3, 5.0, 2.0)
	)


## Neutral pill: a chip whose tint is decided at runtime (activity colour).
static func style_neutral_chip(label: Label) -> void:
	if label == null:
		return
	label.add_theme_font_override("font", body_font())
	label.add_theme_font_size_override("font_size", 11)
	label.add_theme_stylebox_override(
		"normal", make_inset_style(BG_BADGE, BORDER_SUBTLE, 3, 8.0, 3.0)
	)


## Tinted pill: current activity, mood, profession group.
static func style_chip(label: Label, tint: Color) -> void:
	if label == null:
		return
	label.add_theme_font_size_override("font_size", 11)
	label.add_theme_color_override("font_color", tint)
	var box := make_inset_style(
		Color(tint.r, tint.g, tint.b, 0.10),
		Color(tint.r, tint.g, tint.b, 0.28),
		3,
		8.0,
		3.0
	)
	label.add_theme_stylebox_override("normal", box)


# --- stylebox factories ------------------------------------------------------


## Framed surface used by every floating card in the interface.
static func make_panel_style(
	bg: Color = BG_PANEL,
	border: Color = BORDER_BRASS,
	corner_radius: int = PANEL_RADIUS,
	pad_h: float = 18.0,
	pad_v: float = 16.0
) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = bg
	box.set_border_width_all(1)
	box.border_color = border
	box.set_corner_radius_all(corner_radius)
	box.content_margin_left = pad_h
	box.content_margin_right = pad_h
	box.content_margin_top = pad_v
	box.content_margin_bottom = pad_v
	box.shadow_color = Color(0.0, 0.0, 0.0, 0.42)
	box.shadow_size = 12
	box.shadow_offset = Vector2(0.0, 4.0)
	box.anti_aliasing = true
	return box


## Recessed card/badge surface for status pills, metric tiles and chronicle rows.
static func make_inset_style(
	bg: Color = BG_INSET,
	border: Color = BORDER_SUBTLE,
	corner_radius: int = 4,
	pad_h: float = 9.0,
	pad_v: float = 5.0
) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = bg
	box.set_border_width_all(1)
	box.border_color = border
	box.set_corner_radius_all(corner_radius)
	box.content_margin_left = pad_h
	box.content_margin_right = pad_h
	box.content_margin_top = pad_v
	box.content_margin_bottom = pad_v
	box.anti_aliasing = true
	return box


## Hairline rule that replaces the default engine `HSeparator`.
static func make_rule_style() -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = BORDER_SUBTLE
	box.content_margin_top = 1.0
	box.content_margin_bottom = 0.0
	return box


## `ProgressBar` fill: fully rounded, no border, no highlight band.
static func make_bar_fill_style(fill_color: Color) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = fill_color
	box.set_corner_radius_all(3)
	box.anti_aliasing = true
	return box


## `ProgressBar` track: recessed ink well.
static func make_bar_track_style() -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = BG_BAR_TRACK
	box.set_border_width_all(1)
	box.border_color = BORDER_SUBTLE
	box.set_corner_radius_all(3)
	box.anti_aliasing = true
	return box


## Emphasised action inside a modal (Save, Confirm): warm ink, gold rim.
static func style_primary_button(button: Button) -> void:
	if button == null:
		return
	button.add_theme_stylebox_override(
		"normal", make_inset_style(BG_BUTTON_ACTIVE, BORDER_GOLD_BRIGHT, 4, 14.0, 8.0)
	)
	button.add_theme_stylebox_override(
		"hover",
		make_inset_style(BG_BUTTON_ACTIVE.lightened(0.10), BORDER_GOLD_BRIGHT, 4, 14.0, 8.0)
	)
	button.add_theme_stylebox_override(
		"pressed",
		make_inset_style(BG_BUTTON_PRESSED, BORDER_GOLD_BRIGHT, 4, 14.0, 8.0)
	)
	button.add_theme_color_override("font_color", TEXT_GOLD)
	button.add_theme_color_override("font_hover_color", TEXT_PARCHMENT)
	button.add_theme_color_override("font_pressed_color", TEXT_GOLD)


## Left accent bar used to colour-code chronicle entries without tinting text.
static func make_accent_row_style(accent: Color) -> StyleBoxFlat:
	var box := make_inset_style(Color(1.0, 1.0, 1.0, 0.014), BORDER_SUBTLE, 4, 10.0, 7.0)
	box.border_width_left = 2
	box.border_color = Color(accent.r, accent.g, accent.b, 0.55)
	return box


# --- semantic colours --------------------------------------------------------


## Colour for an inhabitant's current activity.
static func color_for_activity(activity: int) -> Color:
	var result := TEXT_PARCHMENT
	match activity:
		NpcRecord.Activity.WORKING:
			result = TEXT_GOLD
		NpcRecord.Activity.EATING:
			result = TEXT_GOOD
		NpcRecord.Activity.SOCIALIZING:
			result = TEXT_CALM
		NpcRecord.Activity.SLEEPING, NpcRecord.Activity.RESTING:
			result = TEXT_LILAC
		NpcRecord.Activity.BLOCKED:
			result = TEXT_CRITICAL
	return result


## Fill colour for the energy bar (100 = rested, <=28 tired).
static func color_for_energy(energy: float) -> Color:
	if energy <= 15.0:
		return Color(0.80, 0.40, 0.35, 1.0)
	if energy <= 32.0:
		return Color(0.84, 0.66, 0.36, 1.0)
	return Color(0.52, 0.74, 0.50, 1.0)


## Fill colour for the hunger bar (0 = full, >=62 hungry, >=88 urgent).
static func color_for_hunger(hunger: float) -> Color:
	if hunger >= 85.0:
		return Color(0.86, 0.42, 0.36, 1.0)
	if hunger >= 60.0:
		return Color(0.86, 0.62, 0.34, 1.0)
	return Color(0.58, 0.70, 0.44, 1.0)


## Fill colour for the wellbeing bar (100 = serene, <40 troubled).
static func color_for_wellbeing(wellbeing: float) -> Color:
	if wellbeing < 35.0:
		return Color(0.82, 0.48, 0.42, 1.0)
	if wellbeing < 60.0:
		return Color(0.78, 0.68, 0.40, 1.0)
	return Color(0.48, 0.68, 0.82, 1.0)


# --- internal theme builders -------------------------------------------------


static func _configure_labels(theme: Theme) -> void:
	theme.set_color("font_color", "Label", TEXT_PARCHMENT)
	theme.set_color("font_color", "ItemList", TEXT_PARCHMENT)
	theme.set_color("font_selected_color", "ItemList", TEXT_GOLD)
	theme.set_color("font_hovered_color", "ItemList", TEXT_GOLD)
	theme.set_stylebox(
		"panel", "ItemList", make_inset_style(BG_INSET, BORDER_SUBTLE, 4, 8.0, 6.0)
	)
	theme.set_stylebox("selected", "ItemList", make_inset_style(BG_BUTTON_HOVER, BORDER_BRASS))
	theme.set_font_size("font_size", "TooltipLabel", 12)


static func _configure_buttons(theme: Theme) -> void:
	var normal := make_inset_style(BG_BUTTON, BORDER_BRASS, 4, 12.0, 7.0)
	var hover := make_inset_style(BG_BUTTON_HOVER, BORDER_GOLD_BRIGHT, 4, 12.0, 7.0)
	var pressed := make_inset_style(BG_BUTTON_PRESSED, BORDER_GOLD_BRIGHT, 4, 12.0, 7.0)
	var disabled := make_inset_style(BG_BUTTON_DISABLED, BORDER_SUBTLE, 4, 12.0, 7.0)
	for control_type in ["Button", "OptionButton"]:
		theme.set_stylebox("normal", control_type, normal)
		theme.set_stylebox("hover", control_type, hover)
		theme.set_stylebox("pressed", control_type, pressed)
		theme.set_stylebox("focus", control_type, hover)
		theme.set_stylebox("disabled", control_type, disabled)
		theme.set_font_size("font_size", control_type, 12)
		theme.set_color("font_color", control_type, TEXT_SECONDARY)
		theme.set_color("font_hover_color", control_type, TEXT_PARCHMENT)
		theme.set_color("font_pressed_color", control_type, TEXT_GOLD)
		theme.set_color("font_focus_color", control_type, TEXT_PARCHMENT)
		theme.set_color("font_disabled_color", control_type, TEXT_MUTED)
	theme.set_stylebox("hover", "OptionButton", hover)


static func _configure_popups(theme: Theme) -> void:
	var panel := make_panel_style(BG_MODAL, BORDER_BRASS, 5, 8.0, 8.0)
	var hover := make_inset_style(BG_BUTTON_HOVER, BORDER_SUBTLE, 3, 8.0, 5.0)
	theme.set_stylebox("panel", "PopupMenu", panel)
	theme.set_stylebox("hover", "PopupMenu", hover)
	theme.set_color("font_color", "PopupMenu", TEXT_SECONDARY)
	theme.set_color("font_hover_color", "PopupMenu", TEXT_PARCHMENT)
	theme.set_color("font_disabled_color", "PopupMenu", TEXT_MUTED)
	theme.set_font_size("font_size", "PopupMenu", 12)
	theme.set_constant("v_separation", "PopupMenu", 4)
	theme.set_constant("item_start_padding", "PopupMenu", 10)
	theme.set_constant("item_end_padding", "PopupMenu", 10)
	theme.set_stylebox("panel", "PopupPanel", panel)


static func _configure_tooltips(theme: Theme) -> void:
	var tip_panel := make_panel_style(BG_MODAL, BORDER_GOLD_BRIGHT, 4, 10.0, 7.0)
	theme.set_stylebox("panel", "TooltipPanel", tip_panel)
	theme.set_color("font_color", "TooltipLabel", TEXT_SECONDARY)


static func _configure_separators(theme: Theme) -> void:
	theme.set_stylebox("separator", "HSeparator", make_rule_style())
	theme.set_constant("separation", "HSeparator", 1)


static func _configure_fields_and_bars(theme: Theme) -> void:
	var field := make_inset_style(BG_INSET, BORDER_SUBTLE, 4, 10.0, 6.0)
	var field_focus := make_inset_style(BG_INSET, BORDER_GOLD_BRIGHT, 4, 10.0, 6.0)
	for control_type in ["LineEdit", "TextEdit"]:
		theme.set_stylebox("normal", control_type, field)
		theme.set_stylebox("focus", control_type, field_focus)
		theme.set_color("font_color", control_type, TEXT_PARCHMENT)
		theme.set_color("font_placeholder_color", control_type, TEXT_MUTED)
		theme.set_color("caret_color", control_type, TEXT_GOLD)
	theme.set_stylebox("background", "ProgressBar", make_bar_track_style())
	theme.set_stylebox("fill", "ProgressBar", make_bar_fill_style(TEXT_GOOD))
	theme.set_color("font_color", "ProgressBar", TEXT_PARCHMENT)


static func _configure_scrollbars(theme: Theme) -> void:
	var track := StyleBoxFlat.new()
	track.bg_color = Color(0.0, 0.0, 0.0, 0.0)
	track.content_margin_left = 3.0
	track.content_margin_right = 3.0
	var grabber := StyleBoxFlat.new()
	grabber.bg_color = Color(0.86, 0.80, 0.66, 0.20)
	grabber.set_corner_radius_all(3)
	var grabber_hot := StyleBoxFlat.new()
	grabber_hot.bg_color = Color(0.88, 0.76, 0.52, 0.42)
	grabber_hot.set_corner_radius_all(3)
	for bar_type in ["VScrollBar", "HScrollBar"]:
		theme.set_stylebox("scroll", bar_type, track)
		theme.set_stylebox("grabber", bar_type, grabber)
		theme.set_stylebox("grabber_highlight", bar_type, grabber_hot)
		theme.set_stylebox("grabber_pressed", bar_type, grabber_hot)
	theme.set_constant("minimum_grab_thickness", "VScrollBar", 28)
	theme.set_constant("minimum_grab_thickness", "HScrollBar", 28)
