Place your tiny LLaMA GGUF model file here, e.g. tinyllama.gguf

Example (TinyLlama 1.1B Chat GGUF):
1. Download a small quantized file (e.g. tinyllama-1.1b-chat-v1.0.Q4_K_M.gguf) from Hugging Face.
2. Rename to tinyllama.gguf and copy into this directory.
3. Ensure pubspec.yaml includes the assets/models/ path.
4. Run `flutter pub get` then restart the app.

The app will copy this asset to application documents and load it for on-device parsing.
