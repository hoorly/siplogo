import os
import subprocess
import shutil
import re

# Настройки путей
PJSIP_SOURCE = "/Users/jocker/Downloads/pjproject-2.17/pjsip/lib/libpjsua2.dylib"
PJ_ROOT = "/Users/jocker/Downloads/pjproject-2.17"
APP_FRAMEWORKS = "/Users/jocker/StudioProjects/siplogo/siplogo/build/macos/Build/Products/Release/siplogo.app/Contents/Frameworks"

os.makedirs(APP_FRAMEWORKS, exist_ok=True)

pjsip_in_app = os.path.join(APP_FRAMEWORKS, "libpjsua2.dylib")
if not os.path.exists(pjsip_in_app):
    shutil.copy(PJSIP_SOURCE, pjsip_in_app)

try:
    BREW_PREFIX = subprocess.check_output(["brew", "--prefix"], text=True).strip()
except Exception:
    BREW_PREFIX = "/opt/homebrew"

def get_dependencies(lib_path):
    try:
        result = subprocess.run(["otool", "-L", lib_path], capture_output=True, text=True, check=True)
        lines = result.stdout.splitlines()
        deps = []
        for line in lines[1:]:
            match = re.match(r'\s*([^\s]+)', line)
            if match:
                deps.append(match.group(1))
        return deps
    except Exception as e:
        print(f"Ошибка otool для {lib_path}: {e}")
        return []

def find_file_everywhere(filename):
    """Ищет точное совпадение файла в PJSIP и Homebrew, разворачивая симлинки"""
    for root, dirs, files in os.walk(PJ_ROOT):
        if filename in files:
            return os.path.join(root, filename)
            
    brew_search_paths = [os.path.join(BREW_PREFIX, "lib"), os.path.join(BREW_PREFIX, "Cellar")]
    for b_path in brew_search_paths:
        if os.path.exists(b_path):
            for root, dirs, files in os.walk(b_path):
                if filename in files:
                    full_path = os.path.join(root, filename)
                    # Разворачиваем символическую ссылку в реальный путь на диске
                    real_path = os.path.realpath(full_path)
                    if os.path.exists(real_path) and os.path.isfile(real_path):
                        return real_path
    return None

def find_fuzzy_fallback(filename):
    """Если точная версия не найдена, ищет альтернативную мажорную версию"""
    match = re.match(r'([a-zA-Z0-9_\-]+)\.\d+\.dylib', filename)
    if not match:
        return None
    base_name = match.group(1)
    
    brew_search_paths = [os.path.join(BREW_PREFIX, "lib"), os.path.join(BREW_PREFIX, "Cellar")]
    candidates = []
    
    for b_path in brew_search_paths:
        if os.path.exists(b_path):
            for root, dirs, files in os.walk(b_path):
                for f in files:
                    if f.startswith(base_name) and f.endswith(".dylib"):
                        full_path = os.path.join(root, f)
                        real_path = os.path.realpath(full_path)
                        if os.path.exists(real_path) and os.path.isfile(real_path):
                            candidates.append(real_path)
    
    if candidates:
        candidates.sort()
        return candidates[-1] # Возвращаем самый свежий доступный файл
    return None

queue = [pjsip_in_app]
processed_libs = set()

print("=== Шаг 1: Рекурсивный поиск и копирование зависимостей ===")

while queue:
    current_lib = queue.pop(0)
    if current_lib in processed_libs:
        continue
    processed_libs.add(current_lib)
    
    dependencies = get_dependencies(current_lib)
    
    for dep in dependencies:
        if dep.startswith("/opt/homebrew") or dep.startswith("/usr/local") or dep.startswith("../") or dep.startswith("../../"):
            filename = os.path.basename(dep)
            target_path = os.path.join(APP_FRAMEWORKS, filename)
            
            if not os.path.exists(target_path):
                src_path = find_file_wherever = find_file_everywhere(filename)
                
                if src_path and os.path.exists(src_path):
                    # Важно: shutil.copy копирует содержимое файла, даже если src_path был симлинком
                    shutil.copy(src_path, target_path)
                    print(f"[Скопировано] {filename} (из реального пути: {src_path})")
                else:
                    fallback_path = find_fuzzy_fallback(filename)
                    if fallback_path and os.path.exists(fallback_path):
                        shutil.copy(fallback_path, target_path)
                        print(f"[🔄 АДАПТИРОВАНО] {filename} (взят файл {os.path.basename(fallback_path)})")
                    else:
                        print(f"[❌ КРИТИЧЕСКАЯ ОШИБКА] Не удалось найти: {filename}")
                        continue
            
            if os.path.exists(target_path) and target_path not in processed_libs:
                queue.append(target_path)

print("\n=== Шаг 2: Выравнивание путей через install_name_tool ===")
for item in os.listdir(APP_FRAMEWORKS):
    if not item.endswith(".dylib") and ".dylib." not in item:
        continue
    lib_path = os.path.join(APP_FRAMEWORKS, item)
    
    subprocess.run(["install_name_tool", "-id", f"@loader_path/{item}", lib_path])
    
    current_deps = get_dependencies(lib_path)
    for dep in current_deps:
        if dep.startswith("/opt/homebrew") or dep.startswith("/usr/local") or dep.startswith("../") or dep.startswith("../../"):
            filename = os.path.basename(dep)
            new_path = f"@loader_path/{filename}"
            subprocess.run(["install_name_tool", "-change", dep, new_path, lib_path])

print("[Готово] Все пути изменены на @loader_path/")

print("\n=== Шаг 3: Переподпись всех библиотек ===")
for item in os.listdir(APP_FRAMEWORKS):
    if item.endswith(".dylib") or ".dylib." in item:
        lib_path = os.path.join(APP_FRAMEWORKS, item)
        subprocess.run(["codesign", "--force", "--sign", "-", lib_path], stderr=subprocess.DEVNULL)
print("[Готово] Все компоненты успешно переподписаны.")