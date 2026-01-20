class_name UIComponentFactory
extends Node

# 组件缓存
var component_cache: Dictionary = {}
var max_cache_size: int = 50

func _ready():
    # 预加载常用组件
    _preload_common_components()

# 创建表单组件
func create_form(parent: Control, config: Dictionary):
    var form = VBoxContainer.new()
    form.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    form.size_flags_vertical = Control.SIZE_EXPAND_FILL
    parent.add_child(form)

    # 添加表单标题
    if config.has("title"):
        var title = Label.new()
        title.text = config.title
        title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
        title.add_theme_font_size_override("font_size", 18)
        form.add_child(title)

        var spacer = Control.new()
        spacer.custom_minimum_size = Vector2(0, 10)
        form.add_child(spacer)

    # 添加表单字段
    var fields = config.get("fields", [])
    for field in fields:
        var field_container = _create_form_field(field)
        form.add_child(field_container)

    # 添加按钮组
    if config.has("buttons"):
        var button_container = HBoxContainer.new()
        button_container.alignment = BoxContainer.ALIGNMENT_CENTER
        form.add_child(button_container)

        var buttons = config.buttons
        for button_config in buttons:
            var button = Button.new()
            button.text = button_config.get("text", "Button")
            button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
            button_container.add_child(button)

            # 连接按钮信号
            button.connect("pressed", Callable(self, "_on_form_button_pressed").bind(button_config))

# 创建按钮组件
func create_button(parent: Control, config: Dictionary):
    var button = Button.new()
    button.text = config.get("text", "Button")
    button.size_flags_horizontal = Control.SIZE_EXPAND_FILL

    # 设置按钮样式
    if config.has("style"):
        _apply_button_style(button, config.style)

    parent.add_child(button)

    # 连接信号
    button.connect("pressed", Callable(self, "_on_button_pressed").bind(config))

# 创建文本组件
func create_text(parent: Control, config: Dictionary):
    print("[UIComponentFactory] Creating text component")
    var text_control = RichTextLabel.new()
    var raw_text = config.get("text", "")
    text_control.bbcode_enabled = true # 启用BBCode支持
    text_control.text = raw_text
    print("[UIComponentFactory] Text content: ", raw_text)
    text_control.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    text_control.size_flags_vertical = Control.SIZE_EXPAND_FILL

    # 设置文本属性
    if config.has("font_size"):
        text_control.add_theme_font_size_override("normal_font_size", config.font_size)

    if config.has("color"):
        text_control.add_theme_color_override("default_color", _parse_color(config.color))

    if config.has("scrollable"):
        text_control.scroll_active = config.scrollable

    parent.add_child(text_control)

# 创建列表组件
func create_list(parent: Control, config: Dictionary):
    var scroll_container = ScrollContainer.new()
    scroll_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    scroll_container.size_flags_vertical = Control.SIZE_EXPAND_FILL
    parent.add_child(scroll_container)

    var item_container = VBoxContainer.new()
    item_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    scroll_container.add_child(item_container)

    # 添加列表项
    var items = config.get("items", [])
    for item in items:
        var item_control = _create_list_item(item)
        item_container.add_child(item_control)

# 创建容器组件
func create_container(parent: Control, config: Dictionary):
    var container_type = config.get("container_type", "vbox")

    var container: Control
    match container_type:
        "vbox":
            container = VBoxContainer.new()
        "hbox":
            container = HBoxContainer.new()
        "grid":
            container = GridContainer.new()
            if config.has("columns"):
                container.columns = config.columns
        "panel":
            container = PanelContainer.new()
        _:
            container = Control.new()

    container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    container.size_flags_vertical = Control.SIZE_EXPAND_FILL

    parent.add_child(container)

    # 添加子组件
    var children = config.get("children", [])
    for child_config in children:
        create_component(container, child_config)

# 创建通用组件
func create_component(parent: Control, config: Dictionary):
    var component_type = config.get("type", "container")

    match component_type:
        "form":
            create_form(parent, config)
        "button":
            create_button(parent, config)
        "text":
            create_text(parent, config)
        "list":
            create_list(parent, config)
        "container":
            create_container(parent, config)
        "input":
            _create_input_field(parent, config)
        "slider":
            _create_slider(parent, config)
        "checkbox":
            _create_checkbox(parent, config)
        "select":
            _create_select(parent, config)
        _:
            create_custom_component(parent, config)

# 创建自定义组件
func create_custom_component(parent: Control, config: Dictionary):
    # 这里可以根据配置创建自定义组件
    var custom_control = Control.new()
    custom_control.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    custom_control.size_flags_vertical = Control.SIZE_EXPAND_FILL

    # 应用自定义样式
    if config.has("custom_style"):
        _apply_custom_style(custom_control, config.custom_style)

    parent.add_child(custom_control)

# 更新组件
func update_component(parent: Control, updates: Dictionary):
    # 遍历所有子节点并应用更新
    for child in parent.get_children():
        _apply_updates_to_component(child, updates)

# 私有辅助方法
func _create_form_field(field_config: Dictionary) -> Control:
    var container = HBoxContainer.new()
    container.size_flags_horizontal = Control.SIZE_EXPAND_FILL

    # 标签
    if field_config.has("label"):
        var label = Label.new()
        label.text = field_config.label
        label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
        label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
        container.add_child(label)

    # 输入控件
    var input_control = _create_input_control(field_config)
    container.add_child(input_control)

    return container

func _create_input_control(field_config: Dictionary) -> Control:
    var input_type = field_config.get("input_type", "text")

    match input_type:
        "text":
            var line_edit = LineEdit.new()
            line_edit.text = field_config.get("value", "")
            line_edit.placeholder_text = field_config.get("placeholder", "")
            line_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
            return line_edit

        "number":
            var spin_box = SpinBox.new()
            spin_box.value = field_config.get("value", 0.0)
            spin_box.min_value = field_config.get("min", 0.0)
            spin_box.max_value = field_config.get("max", 100.0)
            spin_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
            return spin_box

        "password":
            var line_edit = LineEdit.new()
            line_edit.text = field_config.get("value", "")
            line_edit.secret = true
            line_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
            return line_edit

        _:
            var line_edit = LineEdit.new()
            line_edit.text = field_config.get("value", "")
            line_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
            return line_edit

func _create_input_field(parent: Control, config: Dictionary):
    var input = LineEdit.new()
    input.text = config.get("value", "")
    input.placeholder_text = config.get("placeholder", "")
    input.size_flags_horizontal = Control.SIZE_EXPAND_FILL

    if config.has("max_length"):
        input.max_length = config.max_length

    parent.add_child(input)

    # 连接信号
    input.connect("text_changed", Callable(self, "_on_input_text_changed").bind(config))

func _create_slider(parent: Control, config: Dictionary):
    var slider = HSlider.new()
    slider.min_value = config.get("min", 0.0)
    slider.max_value = config.get("max", 100.0)
    slider.value = config.get("value", 50.0)
    slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL

    parent.add_child(slider)

    # 连接信号
    slider.connect("value_changed", Callable(self, "_on_slider_value_changed").bind(config))

func _create_checkbox(parent: Control, config: Dictionary):
    var checkbox = CheckBox.new()
    checkbox.text = config.get("text", "")
    checkbox.button_pressed = config.get("checked", false)

    parent.add_child(checkbox)

    # 连接信号
    checkbox.connect("toggled", Callable(self, "_on_checkbox_toggled").bind(config))

func _create_select(parent: Control, config: Dictionary):
    var option_button = OptionButton.new()

    var options = config.get("options", [])
    for i in range(options.size()):
        var option = options[i]
        if option is Dictionary:
            option_button.add_item(option.get("label", str(option.get("value", ""))), i)
        else:
            option_button.add_item(str(option), i)

    option_button.selected = config.get("selected", 0)
    option_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL

    parent.add_child(option_button)

    # 连接信号
    option_button.connect("item_selected", Callable(self, "_on_option_selected").bind(config))

func _create_list_item(item_config: Dictionary) -> Control:
    var item_container = PanelContainer.new()
    item_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL

    var hbox = HBoxContainer.new()
    item_container.add_child(hbox)

    # 图标（如果有）
    if item_config.has("icon"):
        var icon_texture = load(item_config.icon)
        if icon_texture:
            var icon = TextureRect.new()
            icon.texture = icon_texture
            icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
            hbox.add_child(icon)

    # 标题
    var title_label = Label.new()
    title_label.text = item_config.get("title", "")
    title_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    hbox.add_child(title_label)

    # 描述（如果有）
    if item_config.has("description"):
        var desc_label = Label.new()
        desc_label.text = item_config.description
        desc_label.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7))
        hbox.add_child(desc_label)

    return item_container

# 样式应用方法
func _apply_button_style(button: Button, style_config: Dictionary):
    if style_config.has("color"):
        var style_box = StyleBoxFlat.new()
        style_box.bg_color = _parse_color(style_config.color)
        button.add_theme_stylebox_override("normal", style_box)

    if style_config.has("font_size"):
        button.add_theme_font_size_override("font_size", style_config.font_size)

func _apply_custom_style(control: Control, style_config: Dictionary):
    if style_config.has("background_color"):
        control.modulate = _parse_color(style_config.background_color)

    if style_config.has("size"):
        var size = style_config.size
        if size is Vector2:
            control.custom_minimum_size = size

# 颜色解析
func _parse_color(color_value) -> Color:
    if color_value is String:
        if color_value.begins_with("#"):
            return Color(color_value)
        elif color_value == "red":
            return Color.RED
        elif color_value == "green":
            return Color.GREEN
        elif color_value == "blue":
            return Color.BLUE
        elif color_value == "white":
            return Color.WHITE
        elif color_value == "black":
            return Color.BLACK
        else:
            return Color(color_value)
    elif color_value is Array and color_value.size() >= 3:
        return Color(color_value[0], color_value[1], color_value[2], color_value[3] if color_value.size() > 3 else 1.0)
    else:
        return Color.WHITE

# 事件处理方法
func _on_button_pressed(config: Dictionary):
    _emit_component_event("button_pressed", config)

func _on_form_button_pressed(button_config: Dictionary):
    _emit_component_event("form_button_pressed", button_config)

func _on_input_text_changed(new_text: String, config: Dictionary):
    _emit_component_event("input_changed", {"config": config, "text": new_text})

func _on_slider_value_changed(value: float, config: Dictionary):
    _emit_component_event("slider_changed", {"config": config, "value": value})

func _on_checkbox_toggled(pressed: bool, config: Dictionary):
    _emit_component_event("checkbox_toggled", {"config": config, "checked": pressed})

func _on_option_selected(index: int, config: Dictionary):
    _emit_component_event("option_selected", {"config": config, "index": index})

# 发出组件事件
func _emit_component_event(event_type: String, event_data: Dictionary):
    # 向上传递事件
    var mobile_ui = get_parent().get_parent()
    if mobile_ui and mobile_ui.has_method("_on_ui_component_event"):
        mobile_ui._on_ui_component_event(event_type, event_data)

# 更新应用方法
func _apply_updates_to_component(component: Control, updates: Dictionary):
    if updates.has("text") and component.has_method("set_text"):
        component.set_text(updates.text)

    if updates.has("value") and component.has_method("set_value"):
        component.set_value(updates.value)

    if updates.has("visible"):
        component.visible = updates.visible

    if updates.has("enabled"):
        component.disabled = not updates.enabled

    # 递归更新子组件
    for child in component.get_children():
        _apply_updates_to_component(child, updates)

# 预加载常用组件
func _preload_common_components():
    # 这里可以预加载常用组件以提高性能
    pass

# 获取组件缓存统计
func get_cache_stats() -> Dictionary:
    return {
        "cached_components": component_cache.size(),
        "max_cache_size": max_cache_size
    }

# 清除组件缓存
func clear_cache():
    component_cache.clear()