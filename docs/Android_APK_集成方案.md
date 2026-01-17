# Godot + SenseVoice ASR + FunctionGemma Android APK 集成方案

## 📋 目录

1. [项目概述](#项目概述)
2. [技术架构](#技术架构)
3. [模型准备](#模型准备)
4. [Godot Android插件开发](#godot-android插件开发)
5. [C++后端实现](#c后端实现)
6. [APK打包流程](#apk打包流程)
7. [性能优化](#性能优化)
8. [测试与调试](#测试与调试)
9. [常见问题](#常见问题)

---

## 项目概述

### 目标

将以下组件整合到一个Android APK中：
- ✅ **Godot游戏引擎**：3D萌宠客户端
- ✅ **SenseVoice ASR模型**：端侧语音识别（ONNX格式）
- ✅ **FunctionGemma 270M模型**：端侧LLM工具调用（量化版本）
- ✅ **C++后端逻辑**：替代原有的JS/TypeScript后端

### 技术栈

| 组件 | 技术 | 版本要求 |
|------|------|----------|
| Godot | 4.5+ | 支持Android导出 |
| SenseVoice | ONNX Runtime | Android 7.0+ (API 24+) |
| FunctionGemma | ONNX Runtime / GGML | 量化模型 |
| 后端逻辑 | C++ (GDExtension) | C++17+ |
| 构建工具 | Android NDK | r25c+ |
| 编译工具链 | CMake | 3.22+ |

---

## 技术架构

### 整体架构图

```
┌─────────────────────────────────────────────────────────┐
│                    Android APK                          │
├─────────────────────────────────────────────────────────┤
│                                                           │
│  ┌─────────────────────────────────────────────────┐   │
│  │           Godot Engine (4.5)                    │   │
│  │  - 3D渲染引擎                                    │   │
│  │  - GDScript游戏逻辑                              │   │
│  │  - UI系统                                        │   │
│  └─────────────────────────────────────────────────┘   │
│                        ↕ JNI                            │
│  ┌─────────────────────────────────────────────────┐   │
│  │      GDExtension Plugin (C++)                    │   │
│  │  - ASR接口封装                                    │   │
│  │  - LLM接口封装                                    │   │
│  │  - 音频处理                                       │   │
│  │  - 模型管理                                       │   │
│  └─────────────────────────────────────────────────┘   │
│                        ↕ JNI                            │
│  ┌─────────────────────────────────────────────────┐   │
│  │      Android Native Layer (C++)                 │   │
│  │  ┌──────────────┐  ┌──────────────┐            │   │
│  │  │ ONNX Runtime  │  │  GGML/ONNX   │            │   │
│  │  │ (SenseVoice)  │  │ (FunctionGemma)│           │   │
│  │  └──────────────┘  └──────────────┘            │   │
│  │  ┌──────────────┐  ┌──────────────┐            │   │
│  │  │ 音频处理库    │  │ Tokenizer     │            │   │
│  │  │ (libaudio)   │  │ (SentencePiece)│           │   │
│  │  └──────────────┘  └──────────────┘            │   │
│  └─────────────────────────────────────────────────┘   │
│                                                           │
│  ┌─────────────────────────────────────────────────┐   │
│  │        模型文件 (Assets)                          │   │
│  │  - sensevoice_model.onnx (~50MB)                 │   │
│  │  - functiongemma_model.ggml (~200MB)            │   │
│  │  - tokenizer.bin                                 │   │
│  │  - vocab.json                                    │   │
│  └─────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────┘
```

### 数据流

```
用户语音输入
    ↓
Godot AudioRecorder (GDScript)
    ↓
GDExtension ASRInterface (C++)
    ↓
ONNX Runtime (SenseVoice)
    ↓
识别文本
    ↓
GDExtension LLMInterface (C++)
    ↓
GGML/ONNX Runtime (FunctionGemma)
    ↓
工具调用结果
    ↓
Godot游戏逻辑 (GDScript)
```

---

## 模型准备

### 1. SenseVoice ASR模型

#### 1.1 模型文件清单

从 `VOICE/SenseVoiceSmall-onnx` 目录获取：

```
sensevoice_model/
├── model_quant.onnx          # 量化ONNX模型 (~50MB)
├── config.yaml               # 模型配置
├── tokens.json               # Token映射
├── chn_jpn_yue_eng_ko_spectok.bpe.model  # BPE分词器
└── am.mvn                    # 音频归一化参数
```

#### 1.2 模型优化

**量化检查**：
```bash
# 确认使用量化模型以减小体积
# model_quant.onnx 通常比 model.onnx 小 50-70%
```

**ONNX优化**：
```python
# 使用onnxruntime-tools优化模型
import onnx
from onnxruntime.tools import optimize_model

model = onnx.load("model_quant.onnx")
optimized_model = optimize_model(model, model_type="bert")
onnx.save(optimized_model, "model_quant_optimized.onnx")
```

#### 1.3 模型文件放置

将模型文件放入Godot项目的 `res://models/sensevoice/` 目录：

```
godot-pet/
└── models/
    └── sensevoice/
        ├── model_quant.onnx
        ├── config.yaml
        ├── tokens.json
        ├── chn_jpn_yue_eng_ko_spectok.bpe.model
        └── am.mvn
```

**注意**：在导出APK时，这些文件会被打包到 `assets/` 目录。

---

### 2. FunctionGemma模型

#### 2.1 模型格式选择

**选项A：ONNX格式**（推荐用于Android）
- ✅ 与SenseVoice统一运行时
- ✅ 内存占用可控
- ⚠️ 需要量化到INT8

**选项B：GGML格式**（推荐用于端侧）
- ✅ 专为移动端优化
- ✅ 内存占用更小
- ✅ 支持量化（Q4/Q5/Q8）
- ⚠️ 需要额外的GGML库

#### 2.2 模型转换

**从HuggingFace转换到ONNX**：

```python
# convert_functiongemma_to_onnx.py
from transformers import AutoModelForCausalLM, AutoTokenizer
import torch

model_name = "google/functiongemma-270m-it"
output_dir = "./functiongemma_onnx"

# 加载模型
tokenizer = AutoTokenizer.from_pretrained(model_name)
model = AutoModelForCausalLM.from_pretrained(
    model_name,
    torch_dtype=torch.float16,
    device_map="cpu"
)

# 导出ONNX
dummy_input = tokenizer("Hello", return_tensors="pt")
torch.onnx.export(
    model,
    (dummy_input["input_ids"],),
    f"{output_dir}/model.onnx",
    input_names=["input_ids"],
    output_names=["logits"],
    dynamic_axes={
        "input_ids": {0: "batch", 1: "sequence"},
        "logits": {0: "batch", 1: "sequence"}
    },
    opset_version=14
)

# 量化到INT8
from onnxruntime.quantization import quantize_dynamic, QuantType
quantize_dynamic(
    f"{output_dir}/model.onnx",
    f"{output_dir}/model_quant_int8.onnx",
    weight_type=QuantType.QUInt8
)
```

**转换为GGML格式**：

```bash
# 使用llama.cpp的convert脚本
git clone https://github.com/ggerganov/llama.cpp
cd llama.cpp

# 先转换为GGUF格式（FunctionGemma基于Gemma架构）
python convert-hf-to-gguf.py \
    --outfile functiongemma-270m.gguf \
    --outtype f16 \
    /path/to/functiongemma-270m-it

# 量化到Q4_K_M（推荐平衡）
./quantize functiongemma-270m.gguf functiongemma-270m-q4.gguf Q4_K_M
```

#### 2.3 模型文件清单

**ONNX版本**：
```
functiongemma_onnx/
├── model_quant_int8.onnx    # INT8量化模型 (~200MB)
├── tokenizer.json           # Tokenizer配置
├── tokenizer_config.json    # Tokenizer元数据
└── config.json              # 模型配置
```

**GGML版本**：
```
functiongemma_ggml/
├── functiongemma-270m-q4.gguf  # Q4量化模型 (~150MB)
└── tokenizer.json              # Tokenizer配置
```

#### 2.4 模型文件放置

将模型文件放入Godot项目的 `res://models/functiongemma/` 目录：

```
godot-pet/
└── models/
    └── functiongemma/
        ├── model_quant_int8.onnx  # 或 functiongemma-270m-q4.gguf
        ├── tokenizer.json
        ├── tokenizer_config.json
        └── config.json
```

---

## Godot Android插件开发

### 1. 项目结构

创建GDExtension插件目录结构：

```
godot-pet/
├── addons/
│   └── native_ml/
│       ├── plugin.cfg
│       ├── native_ml.gdextension
│       └── src/
│           ├── CMakeLists.txt
│           ├── asr_interface.cpp
│           ├── asr_interface.h
│           ├── llm_interface.cpp
│           ├── llm_interface.h
│           ├── audio_processor.cpp
│           ├── audio_processor.h
│           └── model_manager.cpp
│           └── model_manager.h
└── models/
    ├── sensevoice/
    └── functiongemma/
```

### 2. plugin.cfg

```ini
[plugin]

name="NativeML"
description="Native ML models integration (ASR + LLM)"
author="Your Name"
version="1.0.0"
script=""
```

### 3. native_ml.gdextension

```json
{
  "entry_symbol": "godot_native_ml_init",
  "compatibility_minimum": "4.5",
  "compatibility_maximum": "4.5",
  "dependencies": [],
  "android": {
    "library": "libnative_ml.so",
    "architectures": ["arm64-v8a", "armeabi-v7a"],
    "dependencies": [
      "libonnxruntime.so",
      "libggml.so"
    ]
  }
}
```

### 4. CMakeLists.txt

```cmake
cmake_minimum_required(VERSION 3.22)
project(native_ml)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

# 查找依赖
find_package(Godot REQUIRED)
find_package(ONNXRuntime REQUIRED)

# 包含目录
include_directories(
    ${GODOT_CPP_INCLUDE}
    ${ONNXRUNTIME_INCLUDE_DIRS}
)

# 源文件
set(SOURCES
    asr_interface.cpp
    llm_interface.cpp
    audio_processor.cpp
    model_manager.cpp
)

# 创建共享库
add_library(native_ml SHARED ${SOURCES})

# 链接库
target_link_libraries(native_ml
    ${GODOT_CPP_LIBRARIES}
    ${ONNXRUNTIME_LIBRARIES}
    # Android特定库
    log
    android
)

# Android特定配置
if(ANDROID)
    # 设置ABI
    set(CMAKE_ANDROID_ARCH_ABI "arm64-v8a")
    
    # 复制模型文件到assets
    file(COPY ${CMAKE_SOURCE_DIR}/../../models/
         DESTINATION ${CMAKE_LIBRARY_OUTPUT_DIRECTORY}/../assets/models/)
endif()
```

### 5. ASR接口实现 (asr_interface.h)

```cpp
#ifndef ASR_INTERFACE_H
#define ASR_INTERFACE_H

#include <godot_cpp/classes/node.hpp>
#include <godot_cpp/core/binder_common.hpp>
#include <godot_cpp/variant/string.hpp>
#include <godot_cpp/variant/packed_byte_array.hpp>

using namespace godot;

class ASRInterface : public Node {
    GDCLASS(ASRInterface, Node)

private:
    void* onnx_session = nullptr;
    bool is_initialized = false;
    String model_path;

public:
    ASRInterface();
    ~ASRInterface();

    // 初始化模型
    bool initialize(const String& model_path);
    
    // 识别音频（PCM格式，16kHz，单声道，16位）
    String recognize(const PackedByteArray& audio_data);
    
    // 流式识别（实时）
    String recognize_streaming(const PackedByteArray& audio_chunk);
    
    // 释放资源
    void cleanup();

protected:
    static void _bind_methods();
};

#endif // ASR_INTERFACE_H
```

### 6. LLM接口实现 (llm_interface.h)

```cpp
#ifndef LLM_INTERFACE_H
#define LLM_INTERFACE_H

#include <godot_cpp/classes/node.hpp>
#include <godot_cpp/core/binder_common.hpp>
#include <godot_cpp/variant/string.hpp>
#include <godot_cpp/variant/dictionary.hpp>
#include <godot_cpp/variant/array.hpp>

using namespace godot;

class LLMInterface : public Node {
    GDCLASS(LLMInterface, Node)

private:
    void* model_context = nullptr;  // ONNX Session 或 GGML Context
    bool is_initialized = false;
    String model_path;
    String tokenizer_path;

public:
    LLMInterface();
    ~LLMInterface();

    // 初始化模型
    bool initialize(const String& model_path, const String& tokenizer_path);
    
    // 生成文本（FunctionGemma格式）
    Dictionary generate(
        const String& user_message,
        const Array& tools,
        const Dictionary& settings
    );
    
    // 解析工具调用
    Dictionary parse_tool_call(const String& response);
    
    // 释放资源
    void cleanup();

protected:
    static void _bind_methods();
};

#endif // LLM_INTERFACE_H
```

### 7. 音频处理器 (audio_processor.h)

```cpp
#ifndef AUDIO_PROCESSOR_H
#define AUDIO_PROCESSOR_H

#include <godot_cpp/variant/packed_byte_array.hpp>
#include <vector>

class AudioProcessor {
public:
    // 转换Godot音频格式到模型输入格式
    static std::vector<float> convert_to_model_input(
        const PackedByteArray& godot_audio,
        int sample_rate,
        int channels
    );
    
    // 音频预处理（归一化、VAD等）
    static std::vector<float> preprocess(
        const std::vector<float>& audio,
        float mean = 0.0f,
        float std = 1.0f
    );
    
    // 分帧处理（用于流式识别）
    static std::vector<std::vector<float>> frame_audio(
        const std::vector<float>& audio,
        int frame_size = 1600,  // 100ms @ 16kHz
        int hop_size = 800      // 50ms overlap
    );
};

#endif // AUDIO_PROCESSOR_H
```

---

## C++后端实现

### 1. ONNX Runtime集成

#### 1.1 下载ONNX Runtime Android库

```bash
# 下载预编译的Android库
wget https://github.com/microsoft/onnxruntime/releases/download/v1.16.3/onnxruntime-android-1.16.3.zip
unzip onnxruntime-android-1.16.3.zip

# 提取库文件
# arm64-v8a/libonnxruntime.so
# armeabi-v7a/libonnxruntime.so
```

#### 1.2 ASR实现 (asr_interface.cpp)

```cpp
#include "asr_interface.h"
#include <onnxruntime_cxx_api.h>
#include <vector>
#include <fstream>

bool ASRInterface::initialize(const String& model_path) {
    if (is_initialized) {
        cleanup();
    }
    
    this->model_path = model_path;
    
    // 初始化ONNX Runtime
    Ort::Env env(ORT_LOGGING_LEVEL_WARNING, "SenseVoiceASR");
    Ort::SessionOptions session_options;
    
    // Android优化选项
    session_options.SetIntraOpNumThreads(4);
    session_options.SetInterOpNumThreads(1);
    session_options.SetGraphOptimizationLevel(
        GraphOptimizationLevel::ORT_ENABLE_ALL
    );
    
    // 创建Session
    std::string model_path_str = model_path.utf8().get_data();
    Ort::Session session(env, model_path_str.c_str(), session_options);
    
    // 保存session指针（需要转换为void*存储）
    onnx_session = new Ort::Session(std::move(session));
    is_initialized = true;
    
    return true;
}

String ASRInterface::recognize(const PackedByteArray& audio_data) {
    if (!is_initialized) {
        return String();
    }
    
    // 转换音频数据
    std::vector<float> audio_float;
    audio_float.reserve(audio_data.size() / 2);
    
    for (int i = 0; i < audio_data.size(); i += 2) {
        int16_t sample = (audio_data[i + 1] << 8) | audio_data[i];
        audio_float.push_back(sample / 32768.0f);
    }
    
    // 预处理（归一化等）
    // ... 实现音频预处理逻辑
    
    // 创建输入Tensor
    Ort::MemoryInfo memory_info = Ort::MemoryInfo::CreateCpu(
        OrtArenaAllocator, OrtMemTypeDefault
    );
    
    std::vector<int64_t> input_shape = {1, (int64_t)audio_float.size()};
    Ort::Value input_tensor = Ort::Value::CreateTensor<float>(
        memory_info,
        audio_float.data(),
        audio_float.size(),
        input_shape.data(),
        input_shape.size()
    );
    
    // 运行推理
    Ort::Session* session = static_cast<Ort::Session*>(onnx_session);
    auto output_tensors = session->Run(
        Ort::RunOptions{nullptr},
        {"input"},  // 输入名称
        &input_tensor,
        1,
        {"output"}, // 输出名称
        1
    );
    
    // 提取输出
    float* output_data = output_tensors[0].GetTensorMutableData<float>();
    // ... 后处理逻辑（解码、分词等）
    
    return String("识别结果");
}

void ASRInterface::cleanup() {
    if (onnx_session) {
        delete static_cast<Ort::Session*>(onnx_session);
        onnx_session = nullptr;
    }
    is_initialized = false;
}
```

### 2. FunctionGemma集成

#### 2.1 使用ONNX Runtime（推荐）

```cpp
#include "llm_interface.h"
#include <onnxruntime_cxx_api.h>
#include <nlohmann/json.hpp>

bool LLMInterface::initialize(
    const String& model_path,
    const String& tokenizer_path
) {
    // 初始化ONNX Runtime
    Ort::Env env(ORT_LOGGING_LEVEL_WARNING, "FunctionGemma");
    Ort::SessionOptions session_options;
    
    // 优化选项
    session_options.SetIntraOpNumThreads(2);  // LLM通常需要更少线程
    session_options.SetGraphOptimizationLevel(
        GraphOptimizationLevel::ORT_ENABLE_ALL
    );
    
    // 创建Session
    std::string model_path_str = model_path.utf8().get_data();
    Ort::Session session(env, model_path_str.c_str(), session_options);
    
    model_context = new Ort::Session(std::move(session));
    
    // 加载Tokenizer
    // ... 实现Tokenizer加载逻辑
    
    is_initialized = true;
    return true;
}

Dictionary LLMInterface::generate(
    const String& user_message,
    const Array& tools,
    const Dictionary& settings
) {
    if (!is_initialized) {
        return Dictionary();
    }
    
    // 构造FunctionGemma格式的输入
    String system_prompt = "You are a model that can do function calling...";
    String full_prompt = system_prompt + "\n\n" + user_message;
    
    // Tokenize
    std::vector<int64_t> input_ids;
    // ... 实现Tokenization
    
    // 创建输入Tensor
    Ort::MemoryInfo memory_info = Ort::MemoryInfo::CreateCpu(
        OrtArenaAllocator, OrtMemTypeDefault
    );
    
    std::vector<int64_t> input_shape = {1, (int64_t)input_ids.size()};
    Ort::Value input_tensor = Ort::Value::CreateTensor<int64_t>(
        memory_info,
        input_ids.data(),
        input_ids.size(),
        input_shape.data(),
        input_shape.size()
    );
    
    // 运行推理（生成循环）
    Ort::Session* session = static_cast<Ort::Session*>(model_context);
    std::vector<int64_t> generated_tokens;
    
    int max_tokens = settings.get("max_tokens", 256);
    for (int i = 0; i < max_tokens; i++) {
        auto output_tensors = session->Run(
            Ort::RunOptions{nullptr},
            {"input_ids"},
            &input_tensor,
            1,
            {"logits"},
            1
        );
        
        // 采样下一个token
        float* logits = output_tensors[0].GetTensorMutableData<float>();
        int next_token = sample_token(logits);
        generated_tokens.push_back(next_token);
        
        // 检查停止条件
        if (next_token == eos_token_id) {
            break;
        }
        
        // 更新输入（用于下一次迭代）
        // ... 实现输入更新逻辑
    }
    
    // Decode
    String generated_text = decode_tokens(generated_tokens);
    
    // 解析工具调用
    Dictionary result;
    result["text"] = generated_text;
    result["tool_calls"] = parse_tool_call(generated_text);
    
    return result;
}
```

#### 2.2 使用GGML（备选方案）

如果选择GGML格式，需要集成llama.cpp的C++接口：

```cpp
#include "ggml.h"
#include "llama.h"

bool LLMInterface::initialize_ggml(
    const String& model_path,
    const String& tokenizer_path
) {
    // 加载GGML模型
    llama_model_params model_params = llama_model_default_params();
    llama_model* model = llama_load_model_from_file(
        model_path.utf8().get_data(),
        model_params
    );
    
    if (!model) {
        return false;
    }
    
    // 创建Context
    llama_context_params ctx_params = llama_context_default_params();
    ctx_params.n_ctx = 2048;  // 上下文长度
    ctx_params.n_threads = 4;
    
    llama_context* ctx = llama_new_context_with_model(model, ctx_params);
    
    model_context = ctx;
    is_initialized = true;
    return true;
}
```

### 3. 模型管理器 (model_manager.cpp)

```cpp
#include "model_manager.h"
#include <godot_cpp/classes/file_access.hpp>
#include <godot_cpp/classes/project_settings.hpp>
#include <fstream>

String ModelManager::get_model_path(const String& model_name) {
    // 从assets目录加载模型
    String assets_path = "res://models/" + model_name;
    
    // Android上需要从assets复制到可写目录
    #ifdef ANDROID_ENABLED
    String cache_path = OS::get_singleton()->get_user_data_dir() + "/models/";
    String full_path = cache_path + model_name;
    
    // 检查是否已复制
    if (!FileAccess::file_exists(full_path)) {
        // 从assets复制到缓存目录
        copy_from_assets(assets_path, full_path);
    }
    
    return full_path;
    #else
    return ProjectSettings::get_singleton()->globalize_path(assets_path);
    #endif
}

void ModelManager::copy_from_assets(
    const String& src_path,
    const String& dst_path
) {
    // 创建目标目录
    String dir = dst_path.get_base_dir();
    DirAccess::make_dir_recursive_absolute(dir);
    
    // 从assets读取
    Ref<FileAccess> src = FileAccess::open(src_path, FileAccess::READ);
    if (!src.is_valid()) {
        return;
    }
    
    // 写入缓存目录
    Ref<FileAccess> dst = FileAccess::open(dst_path, FileAccess::WRITE);
    if (!dst.is_valid()) {
        return;
    }
    
    // 复制数据
    PackedByteArray data = src->get_buffer(src->get_length());
    dst->store_buffer(data);
}
```

---

## APK打包流程

### 1. 准备Android导出模板

#### 1.1 下载Godot Android导出模板

1. 打开Godot编辑器
2. 编辑器 → 项目 → 导出
3. 添加Android平台
4. 下载导出模板（如果未下载）

#### 1.2 配置导出设置

在Godot项目设置中配置：

```
[application]

config/name="Godot Pet with ML"
run/main_scene="res://scenes/main.tscn"

[export]

presets/android/package="com.yourcompany.godotpet"
presets/android/version/code=1
presets/android/version/name="1.0.0"
presets/android/architectures/armeabi-v7a=false
presets/android/architectures/arm64-v8a=true
presets/android/architectures/x86=false
presets/android/architectures/x86_64=false
presets/android/min_sdk_version=24
presets/android/target_sdk_version=34
```

### 2. 集成Native库

#### 2.1 创建Android插件结构

```
android/
└── plugins/
    └── NativeML/
        ├── build.gradle
        ├── src/
        │   └── main/
        │       ├── AndroidManifest.xml
        │       └── jniLibs/
        │           ├── arm64-v8a/
        │           │   ├── libnative_ml.so
        │           │   ├── libonnxruntime.so
        │           │   └── libggml.so (可选)
        │           └── armeabi-v7a/
        │               ├── libnative_ml.so
        │               ├── libonnxruntime.so
        │               └── libggml.so (可选)
        └── plugin.gdap
```

#### 2.2 plugin.gdap

```ini
[config]

name="NativeML"
binary_type="local"
binary="NativeML/native_ml.gdextension"

[dependencies]

local=["NativeML/libnative_ml.so", "NativeML/libonnxruntime.so"]

[plist]

NSMicrophoneUsageDescription="需要麦克风权限进行语音识别"
```

#### 2.3 build.gradle

```gradle
plugins {
    id 'com.android.library'
}

android {
    namespace 'com.yourcompany.nativeml'
    compileSdk 34

    defaultConfig {
        minSdk 24
        targetSdk 34
    }

    buildTypes {
        release {
            minifyEnabled false
        }
    }
}

dependencies {
    // ONNX Runtime (如果使用AAR)
    // implementation 'com.microsoft.onnxruntime:onnxruntime-android:1.16.3'
}
```

### 3. 模型文件打包

#### 3.1 将模型文件添加到项目

在Godot编辑器中：
1. 将模型文件放入 `res://models/` 目录
2. 在导出设置中，确保这些文件被包含

#### 3.2 导出配置

在导出预设中：
- ✅ 包含所有资源文件
- ✅ 包含模型文件（.onnx, .gguf, .json等）
- ✅ 启用压缩（可选，但会增加加载时间）

### 4. 构建APK

#### 4.1 使用Godot编辑器导出

1. 编辑器 → 项目 → 导出
2. 选择Android平台
3. 配置签名（如果需要）
4. 点击"导出项目"
5. 选择输出路径（.apk文件）

#### 4.2 使用命令行导出

```bash
# Windows PowerShell
godot --headless --export-release "Android" "godot-pet.apk"

# 或使用导出预设
godot --headless --export-release "Android" "godot-pet.apk" --export-preset "Android"
```

### 5. 验证APK内容

```bash
# 解压APK查看内容
unzip -l godot-pet.apk | grep -E "(models|\.so|\.onnx|\.gguf)"

# 应该看到：
# - lib/arm64-v8a/libnative_ml.so
# - lib/arm64-v8a/libonnxruntime.so
# - assets/models/sensevoice/model_quant.onnx
# - assets/models/functiongemma/model_quant_int8.onnx
```

---

## 性能优化

### 1. 模型加载优化

#### 1.1 延迟加载

```cpp
// 不在初始化时加载所有模型
// 按需加载
class ModelManager {
    void load_asr_model() {
        if (!asr_loaded) {
            asr_interface->initialize(get_model_path("sensevoice/model.onnx"));
            asr_loaded = true;
        }
    }
    
    void load_llm_model() {
        if (!llm_loaded) {
            llm_interface->initialize(
                get_model_path("functiongemma/model.onnx"),
                get_model_path("functiongemma/tokenizer.json")
            );
            llm_loaded = true;
        }
    }
};
```

#### 1.2 模型预热

```cpp
// 在后台线程预热模型
void warmup_models() {
    // 使用虚拟输入预热
    PackedByteArray dummy_audio;
    dummy_audio.resize(16000);  // 1秒音频
    asr_interface->recognize(dummy_audio);
    
    String dummy_text = "test";
    llm_interface->generate(dummy_text, Array(), Dictionary());
}
```

### 2. 内存优化

#### 2.1 使用量化模型

- SenseVoice: INT8量化（~50MB）
- FunctionGemma: INT8或Q4量化（~150-200MB）

#### 2.2 模型卸载

```cpp
// 当不需要时卸载模型
void unload_unused_models() {
    if (!asr_in_use) {
        asr_interface->cleanup();
        asr_loaded = false;
    }
    
    if (!llm_in_use) {
        llm_interface->cleanup();
        llm_loaded = false;
    }
}
```

### 3. 推理优化

#### 3.1 批处理

```cpp
// 合并多个音频块进行批处理
std::vector<PackedByteArray> audio_batch;
// ... 收集音频块
String result = asr_interface->recognize_batch(audio_batch);
```

#### 3.2 线程池

```cpp
// 使用线程池处理推理
#include <thread>
#include <queue>

class InferenceThreadPool {
    std::vector<std::thread> workers;
    std::queue<std::function<void()>> tasks;
    
    void worker_thread() {
        while (true) {
            std::function<void()> task;
            {
                std::unique_lock<std::mutex> lock(queue_mutex);
                condition.wait(lock, [this] { return !tasks.empty(); });
                task = tasks.front();
                tasks.pop();
            }
            task();
        }
    }
};
```

### 4. 音频处理优化

#### 4.1 流式处理

```cpp
// 使用滑动窗口进行流式识别
class StreamingASR {
    std::deque<float> audio_buffer;
    const int window_size = 16000;  // 1秒
    
    String process_chunk(const std::vector<float>& chunk) {
        // 添加到缓冲区
        audio_buffer.insert(audio_buffer.end(), chunk.begin(), chunk.end());
        
        // 保持窗口大小
        if (audio_buffer.size() > window_size * 2) {
            audio_buffer.erase(
                audio_buffer.begin(),
                audio_buffer.begin() + (audio_buffer.size() - window_size)
            );
        }
        
        // 识别
        std::vector<float> window(
            audio_buffer.end() - window_size,
            audio_buffer.end()
        );
        return recognize(window);
    }
};
```

---

## 测试与调试

### 1. 单元测试

#### 1.1 ASR测试

```gdscript
# test_asr.gd
extends Node

func _ready():
    var asr = $ASRInterface
    assert(asr.initialize("res://models/sensevoice/model.onnx"))
    
    # 加载测试音频
    var audio_file = FileAccess.open("res://test_audio.pcm", FileAccess.READ)
    var audio_data = audio_file.get_buffer(audio_file.get_length())
    audio_file.close()
    
    var result = asr.recognize(audio_data)
    print("ASR Result: ", result)
    assert(result.length() > 0)
```

#### 1.2 LLM测试

```gdscript
# test_llm.gd
extends Node

func _ready():
    var llm = $LLMInterface
    assert(llm.initialize(
        "res://models/functiongemma/model.onnx",
        "res://models/functiongemma/tokenizer.json"
    ))
    
    var tools = [
        {
            "name": "animate_avatar",
            "description": "控制角色动画",
            "parameters": {
                "type": "object",
                "properties": {
                    "actions": {"type": "array", "items": {"type": "string"}}
                }
            }
        }
    ]
    
    var result = llm.generate("让角色挥手", tools, {"max_tokens": 128})
    print("LLM Result: ", result)
    assert(result.has("tool_calls"))
```

### 2. 性能测试

#### 2.1 基准测试

```cpp
// benchmark.cpp
#include <chrono>

void benchmark_asr() {
    auto start = std::chrono::high_resolution_clock::now();
    
    for (int i = 0; i < 100; i++) {
        asr_interface->recognize(test_audio);
    }
    
    auto end = std::chrono::high_resolution_clock::now();
    auto duration = std::chrono::duration_cast<std::chrono::milliseconds>(
        end - start
    );
    
    printf("ASR Average: %ld ms\n", duration.count() / 100);
}

void benchmark_llm() {
    auto start = std::chrono::high_resolution_clock::now();
    
    for (int i = 0; i < 10; i++) {
        llm_interface->generate(test_prompt, tools, settings);
    }
    
    auto end = std::chrono::high_resolution_clock::now();
    auto duration = std::chrono::duration_cast<std::chrono::milliseconds>(
        end - start
    );
    
    printf("LLM Average: %ld ms\n", duration.count() / 10);
}
```

### 3. 调试工具

#### 3.1 Logcat监控

```bash
# 过滤相关日志
adb logcat | grep -E "(Godot|NativeML|ONNX|ASR|LLM)"
```

#### 3.2 内存分析

```bash
# 使用Android Studio Profiler
# 或使用adb命令
adb shell dumpsys meminfo com.yourcompany.godotpet
```

---

## 常见问题

### 1. 模型加载失败

**问题**：模型文件找不到或加载失败

**解决方案**：
- 检查模型文件是否在 `res://models/` 目录
- 确认导出时模型文件被包含
- 检查文件路径大小写（Android区分大小写）
- 使用 `ModelManager::get_model_path()` 获取正确路径

### 2. 内存不足

**问题**：APK运行时内存溢出

**解决方案**：
- 使用量化模型（INT8/Q4）
- 实现模型延迟加载和卸载
- 减少批处理大小
- 优化音频缓冲区大小

### 3. 推理速度慢

**问题**：ASR或LLM推理耗时过长

**解决方案**：
- 使用量化模型
- 优化ONNX Runtime线程数
- 使用流式处理（减少每次处理的数据量）
- 考虑使用GGML格式（对移动端更友好）

### 4. 音频格式不匹配

**问题**：ASR识别结果不准确

**解决方案**：
- 确认音频格式：16kHz，单声道，16位PCM
- 检查音频预处理（归一化、VAD等）
- 验证模型输入格式与文档一致

### 5. 工具调用解析失败

**问题**：FunctionGemma输出无法解析

**解决方案**：
- 检查FunctionGemma格式（`<start_function_call>...<end_function_call>`）
- 实现更健壮的解析逻辑（正则表达式+错误恢复）
- 验证Tokenizer配置正确

### 6. APK体积过大

**问题**：APK文件超过100MB

**解决方案**：
- 使用Android App Bundle (AAB)格式
- 压缩模型文件（如果支持）
- 移除未使用的资源
- 考虑模型按需下载

---

## 附录

### A. 依赖库版本

| 库 | 版本 | 下载地址 |
|----|------|----------|
| ONNX Runtime | 1.16.3+ | https://github.com/microsoft/onnxruntime |
| Godot C++ Bindings | 4.5 | 随Godot版本 |
| Android NDK | r25c+ | https://developer.android.com/ndk |
| CMake | 3.22+ | https://cmake.org |

### B. 参考资源

- [Godot Android插件开发文档](https://docs.godotengine.org/en/stable/tutorials/plugins/android/index.html)
- [ONNX Runtime Android部署指南](https://onnxruntime.ai/docs/tutorials/mobile/)
- [FunctionGemma官方文档](https://ai.google.dev/gemma/docs/functiongemma)
- [SenseVoice ONNX导出指南](https://github.com/FunAudioLLM/SenseVoice)

### C. 示例代码仓库

（可以添加你的GitHub仓库链接）

---

## 总结

本方案提供了将Godot项目、SenseVoice ASR模型和FunctionGemma模型整合到单个Android APK的完整流程。关键步骤包括：

1. ✅ **模型准备**：转换为ONNX/GGML格式并量化
2. ✅ **插件开发**：使用GDExtension创建C++接口
3. ✅ **后端实现**：集成ONNX Runtime进行推理
4. ✅ **APK打包**：配置导出设置并集成Native库
5. ✅ **性能优化**：延迟加载、量化、流式处理

通过遵循本方案，你可以创建一个完全端侧运行的智能语音交互应用，无需依赖云端服务。

---

**文档版本**: 1.0  
**最后更新**: 2024年  
**作者**: Your Name
