class_name UiTheme
extends RefCounted
## Shared visual theme for EVERAFTER's medieval fantasy civilization UI.
##
## Centralises palette, typography (`SystemFont` + `FontVariation`, keeping the
## repository 100% text-only with zero binary font imports) and `StyleBoxFlat`
## presets so `WorldHud`, `EconomyPanel`, `NpcPanel`, `SaveLoadPanel` and
## `DiagnosticsHud` share a cohesive parchment-and-walnut aesthetic instead of
## looking like default engine debug widgets.

const BG_PANEL := Color(0.075, 0.062, 0.052, 0.94)
const BG_HUD := Color(0.075, 0.062, 0.052, 0.90)
const BG_MODAL := Color(0.055, 0.047, 0.039, 0.97)
const BG_INSET := Color(0.105, 0.087, 0.070, 0.96)
const BG_BADGE := Color(0.16, 0.13, 0.10, 0.96)
const BG_BAR_TRACK := Color(0.10, 0.085, 0.072, 0.98)

const BG_BUTTON := Color(0.15, 0.12, 0.095, 0.95)
const BG_BUTTON_HOVER := Color(0.22, 0.175, 0.13, 0.98)
const BG_BUTTON_PRESSED := Color(0.10, 0.08, 0.065, 0.98)
const BG_BUTTON_DISABLED := Color(0.10, 0.09, 0.08, 0.60)
const BG_BUTTON_ACTIVE := Color(0.28, 0.21, 0.12, 0.98)

const BORDER_BRASS := Color(0.66, 0.53, 0.30, 0.86)
const BORDER_GOLD_BRIGHT := Color(0.88, 0.74, 0.42, 0.95)
const BORDER_SUBTLE := Color(0.42, 0.34, 0.22, 0.52)

const TEXT_GOLD := Color(0.96, 0.88, 0.64, 1.0)
const TEXT_PARCHMENT := Color(0.94, 0.90, 0.82, 1.0)
const TEXT_SECONDARY := Color(0.80, 0.77, 0.69, 1.0)
const TEXT_MUTED := Color(0.68, 0.65, 0.58, 1.0)
const TEXT_GOOD := Color(0.62, 0.84, 0.52, 1.0)
const TEXT_WARN := Color(0.94, 0.74, 0.38, 1.0)
const TEXT_CRITICAL := Color(0.92, 0.46, 0.38, 1.0)
const TEXT_CALM := Color(0.60, 0.78, 0.90, 1.0)

static var _shared_theme: Theme = null
static var _header_font: Font = null
static var _body_font: Font = null


## Returns the singleton `Theme` applied to root UI controls.
static func shared_theme() -> Theme:
	if _shared_theme != null:
		return _shared_theme
	var theme := Theme.new()
	var body := body_font()
	theme.default_font = body
	theme.default_font_size = 13
	_configure_buttons(theme)
	_configure_popups(theme)
	_configure_tooltips(theme)
	_configure_separators(theme)
	_configure_fields_and_bars(theme)
	# Consistent dense-information defaults for labels and lists; bespoke title
	# hierarchy remains applied by the semantic helpers below.
	theme.set_color("font_color", "Label", TEXT_PARCHMENT)
	theme.set_color("font_color", "ItemList", TEXT_PARCHMENT)
	theme.set_color("font_selected_color", "ItemList", TEXT_GOLD)
	theme.set_color("font_hovered_color", "ItemList", TEXT_GOLD)
	theme.set_stylebox("focus", "LineEdit", make_inset_style(BG_INSET, BORDER_GOLD_BRIGHT, 4, 8.0, 5.0))
	_shared_theme = theme
	return _shared_theme


## Serif font variation with subtle glyph spacing for medieval titles/headers.
static func header_font() -> Font:
	if _header_font != null:
		return _header_font
	var sys := SystemFont.new()
	sys.font_names = PackedStringArray([
		"Georgia",
		"Palatino Linotype",
		"Book Antiqua",
		"Constantia",
		"Garamond",
		"Noto Serif",
		"DejaVu Serif",
	])
	sys.antialiasing = TextServer.FONT_ANTIALIASING_GRAY
	var variation := FontVariation.new()
	variation.base_font = sys
	variation.variation_embolden = 0.22
	variation.spacing_glyph = 1
	_header_font = variation
	return _header_font


## Clean humanist sans-serif font stack for dense tables, bars and logs.
static func body_font() -> Font:
	if _body_font != null:
		return _body_font
	var sys := SystemFont.new()
	sys.font_names = PackedStringArray([
		"Segoe UI",
		"Candara",
		"Calibri",
		"Noto Sans",
		"DejaVu Sans",
	])
	sys.antialiasing = TextServer.FONT_ANTIALIASING_GRAY
	_body_font = sys
	return _body_font


## Applies the medieval header font, gold colour and subtle shadow to a Label.
static func style_title_label(label: Label, font_size: int = 16) -> void:
	if label == null:
		return
	label.add_theme_font_override("font", header_font())
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", TEXT_GOLD)
	label.add_theme_color_override("font_shadow_color", Color(0.02, 0.02, 0.01, 0.75))
	label.add_theme_constant_override("shadow_offset_x", 1)
	label.add_theme_constant_override("shadow_offset_y", 1)


## Applies section-header styling (`BISOGNI`, `RELAZIONI`, `RICORDI`, etc.).
static func style_section_label(label: Label, font_size: int = 12) -> void:
	if label == null:
		return
	label.add_theme_font_override("font", header_font())
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", TEXT_GOLD)


## Builds a framed medieval panel `StyleBoxFlat` with subtle shadow and brass rim.
static func make_panel_style(
	bg: Color = BG_PANEL,
	border: Color = BORDER_BRASS,
	corner_radius: int = 8,
	pad_h: float = 14.0,
	pad_v: float = 12.0
) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = bg
	box.border_width_left = 1
	box.border_width_top = 2
	box.border_width_right = 1
	box.border_width_bottom = 2
	box.border_color = border
	box.corner_radius_top_left = corner_radius
	box.corner_radius_top_right = corner_radius
	box.corner_radius_bottom_right = corner_radius
	box.corner_radius_bottom_left = corner_radius
	box.content_margin_left = pad_h
	box.content_margin_right = pad_h
	box.content_margin_top = pad_v
	box.content_margin_bottom = pad_v
	box.shadow_color = Color(0.0, 0.0, 0.0, 0.38)
	box.shadow_size = 6
	box.shadow_offset = Vector2(0.0, 2.0)
	return box


## Builds an inset card/badge `StyleBoxFlat` for status pills and chronicle rows.
static func make_inset_style(
	bg: Color = BG_INSET,
	border: Color = BORDER_SUBTLE,
	corner_radius: int = 5,
	pad_h: float = 8.0,
	pad_v: float = 5.0
) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = bg
	box.border_width_left = 1
	box.border_width_top = 1
	box.border_width_right = 1
	box.border_width_bottom = 1
	box.border_color = border
	box.corner_radius_top_left = corner_radius
	box.corner_radius_top_right = corner_radius
	box.corner_radius_bottom_right = corner_radius
	box.corner_radius_bottom_left = corner_radius
	box.content_margin_left = pad_h
	box.content_margin_right = pad_h
	box.content_margin_top = pad_v
	box.content_margin_bottom = pad_v
	return box


## Builds a `ProgressBar` fill style in the given colour.
static func make_bar_fill_style(fill_color: Color) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = fill_color
	box.border_width_top = 1
	box.border_color = fill_color.lightened(0.22)
	box.corner_radius_top_left = 4
	box.corner_radius_top_right = 4
	box.corner_radius_bottom_right = 4
	box.corner_radius_bottom_left = 4
	return box


## Builds a `ProgressBar` background track style.
static func make_bar_track_style() -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = BG_BAR_TRACK
	box.border_width_left = 1
	box.border_width_top = 1
	box.border_width_right = 1
	box.border_width_bottom = 1
	box.border_color = BORDER_SUBTLE
	box.corner_radius_top_left = 4
	box.corner_radius_top_right = 4
	box.corner_radius_bottom_right = 4
	box.corner_radius_bottom_left = 4
	return box


## Semantic colour for an NPC's current activity.
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
			result = Color(0.72, 0.78, 0.92, 1.0)
		NpcRecord.Activity.BLOCKED:
			result = TEXT_CRITICAL
	return result


## Semantic fill colour for `EnergyBar` (100 = rested, <=28 tired).
static func color_for_energy(energy: float) -> Color:
	if energy <= 15.0:
		return Color(0.84, 0.34, 0.28, 1.0)
	if energy <= 32.0:
		return Color(0.86, 0.64, 0.26, 1.0)
	return Color(0.42, 0.70, 0.36, 1.0)


## Semantic fill colour for `HungerBar` (0 = full, >=62 hungry, >=88 urgent).
static func color_for_hunger(hunger: float) -> Color:
	if hunger >= 85.0:
		return Color(0.88, 0.34, 0.26, 1.0)
	if hunger >= 60.0:
		return Color(0.88, 0.60, 0.24, 1.0)
	return Color(0.56, 0.68, 0.36, 1.0)


## Semantic fill colour for `WellbeingBar` (100 = serene, <40 troubled).
static func color_for_wellbeing(wellbeing: float) -> Color:
	if wellbeing < 35.0:
		return Color(0.82, 0.44, 0.38, 1.0)
	if wellbeing < 60.0:
		return Color(0.78, 0.68, 0.36, 1.0)
	return Color(0.40, 0.64, 0.80, 1.0)


# --- internal theme builders -------------------------------------------------


static func _configure_buttons(theme: Theme) -> void:
	var normal := make_inset_style(BG_BUTTON, BORDER_BRASS, 5, 10.0, 6.0)
	var hover := make_inset_style(BG_BUTTON_HOVER, BORDER_GOLD_BRIGHT, 5, 10.0, 6.0)
	var pressed := make_inset_style(BG_BUTTON_PRESSED, BORDER_GOLD_BRIGHT, 5, 10.0, 6.0)
	var disabled := make_inset_style(BG_BUTTON_DISABLED, BORDER_SUBTLE, 5, 10.0, 6.0)
	for control_type in ["Button", "OptionButton"]:
		theme.set_stylebox("normal", control_type, normal)
		theme.set_stylebox("hover", control_type, hover)
		theme.set_stylebox("pressed", control_type, pressed)
		theme.set_stylebox("focus", control_type, hover)
		theme.set_stylebox("disabled", control_type, disabled)
		theme.set_color("font_color", control_type, TEXT_PARCHMENT)
		theme.set_color("font_hover_color", control_type, TEXT_GOLD)
		theme.set_color("font_pressed_color", control_type, TEXT_GOLD)
		theme.set_color("font_focus_color", control_type, TEXT_PARCHMENT)
		theme.set_color("font_disabled_color", control_type, TEXT_MUTED)


static func _configure_popups(theme: Theme) -> void:
	var panel := make_panel_style(BG_MODAL, BORDER_BRASS, 6, 8.0, 8.0)
	var hover := make_inset_style(BG_BUTTON_HOVER, BORDER_SUBTLE, 4, 6.0, 4.0)
	theme.set_stylebox("panel", "PopupMenu", panel)
	theme.set_stylebox("hover", "PopupMenu", hover)
	theme.set_color("font_color", "PopupMenu", TEXT_PARCHMENT)
	theme.set_color("font_hover_color", "PopupMenu", TEXT_GOLD)
	theme.set_color("font_disabled_color", "PopupMenu", TEXT_MUTED)


static func _configure_tooltips(theme: Theme) -> void:
	var tip_panel := make_panel_style(BG_MODAL, BORDER_GOLD_BRIGHT, 5, 10.0, 6.0)
	theme.set_stylebox("panel", "TooltipPanel", tip_panel)
	theme.set_color("font_color", "TooltipLabel", TEXT_PARCHMENT)
	theme.set_font_size("font_size", "TooltipLabel", 12)


static func _configure_separators(theme: Theme) -> void:
	var sep := StyleBoxFlat.new()
	sep.bg_color = BORDER_SUBTLE
	sep.content_margin_top = 1.0
	sep.content_margin_bottom = 1.0
	theme.set_stylebox("separator", "HSeparator", sep)
	theme.set_constant("separation", "HSeparator", 8)


static func _configure_fields_and_bars(theme: Theme) -> void:
	var field := make_inset_style(BG_INSET, BORDER_SUBTLE, 4, 8.0, 5.0)
	var field_focus := make_inset_style(BG_INSET, BORDER_GOLD_BRIGHT, 4, 8.0, 5.0)
	var bar_track := make_inset_style(BG_BAR_TRACK, BORDER_SUBTLE, 4, 2.0, 2.0)
	var bar_fill := make_bar_fill_style(TEXT_GOOD)
	for control_type in ["LineEdit", "TextEdit"]:
		theme.set_stylebox("normal", control_type, field)
		theme.set_stylebox("focus", control_type, field_focus)
		theme.set_color("font_color", control_type, TEXT_PARCHMENT)
		theme.set_color("font_placeholder_color", control_type, TEXT_MUTED)
		theme.set_color("caret_color", control_type, TEXT_GOLD)
	for control_type in ["ProgressBar"]:
		theme.set_stylebox("background", control_type, bar_track)
		theme.set_stylebox("fill", control_type, bar_fill)
		theme.set_color("font_color", control_type, TEXT_PARCHMENT)
	# A restrained hover lift: brighter brass edge, not glow or animation.
	var active := make_inset_style(BG_BUTTON_ACTIVE, BORDER_GOLD_BRIGHT, 5, 10.0, 6.0)
	theme.set_stylebox("pressed", "Button", active)
	theme.set_stylebox("hover", "OptionButton", make_inset_style(BG_BUTTON_HOVER, BORDER_GOLD_BRIGHT, 5, 10.0, 6.0))
