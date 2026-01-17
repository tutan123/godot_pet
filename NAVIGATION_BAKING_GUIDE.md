# Godot导航网格烘焙指南

## 🎯 为什么需要烘焙导航网格

导航网格烘焙是将3D场景中的几何体转换为AI可以使用的路径规划数据的过程。在Godot中，这个过程需要在编辑器中手动完成。

## 📋 烘焙步骤

### 1. 打开Godot编辑器
启动Godot编辑器，打开 `scenes/main.tscn` 场景。

### 2. 选择NavigationRegion3D节点
在场景树中找到并选中 `NavigationRegion3D` 节点：

```
Main
└── NavigationRegion3D  ← 选择这个节点
    └── Floor
        ├── MeshInstance3D
        └── CollisionShape3D
```

### 3. 打开NavigationMesh属性
在属性面板（Inspector）中，找到 `NavigationMesh` 属性。
你应该能看到一个NavigationMesh资源的预览。

### 4. 点击烘焙按钮
在NavigationMesh资源的属性面板底部，找到 **"Bake NavigationMesh"** 按钮。
点击它开始烘焙过程。

### 5. 等待烘焙完成
烘焙过程可能需要几秒钟。完成后，你应该能在预览中看到生成的导航网格（蓝色的多边形）。

### 6. 保存场景
烘焙完成后，**务必保存场景** (`Ctrl+S`)，这样烘焙的数据才会保存到文件中。

## 🔍 验证烘焙结果

烘焙完成后，你应该能看到：

1. **可视化网格**：场景中显示蓝色的导航多边形
2. **顶点数据**：在Godot控制台或运行时日志中显示顶点和多边形数量
3. **路径查找成功**：EQS查询不再显示"No path found"错误

## ⚠️ 常见问题

### 问题1：烘焙后没有网格显示
**原因**：几何体设置不当
**解决**：确保Floor是NavigationRegion3D的子节点，且有有效的MeshInstance3D

### 问题2：烘焙失败或空网格
**原因**：参数设置不合适
**解决**：检查agent_height, agent_radius等参数是否合理

### 问题3：路径查找仍然失败
**原因**：烘焙数据未保存
**解决**：确保保存了场景，烘焙的vertices和polygons数据应该出现在.tscn文件中

## 🔧 烘焙参数说明

```gdscript
cell_size = 0.05          # 网格单元大小，越小精度越高但性能越差
cell_height = 0.05        # 高度单元大小
agent_height = 1.0        # AI代理的高度
agent_radius = 0.2        # AI代理的半径
agent_max_climb = 0.2     # 能爬上的最大高度
agent_max_slope = 30.0    # 能走的坡度角度
region_min_size = 0.5     # 区域最小尺寸
region_merge_size = 10.0  # 区域合并尺寸
```

## 🎮 测试烘焙效果

烘焙完成后，运行游戏并测试EQS查询。你应该在控制台看到：

```
[System] Navigation mesh is ready with X vertices and Y polygons
[EQS] Path found with length: Z
[EQS] Pathfinding score: 0.XXX
```

而不是：
```
[EQS] No path found from ... to ...
```

## 💡 提示

- **烘焙是编辑时操作**：在Godot编辑器中完成，不是运行时
- **保存很重要**：烘焙数据存储在场景文件中
- **参数调整**：如果烘焙效果不好，可以调整agent参数后重新烘焙
- **可视化调试**：烘焙后可以在编辑器中看到导航网格的形状