Установи free-claude-code (https://github.com/Alishahryar1/free-claude-code)
и настрой работу через DeepSeek параллельно с обычным claude.

1. Клонируй репо и поставь: uv tool install --force .
2. Скопируй .env.example → .env, в нём:
   - DEEPSEEK_API_KEY="<спроси у меня>"
   - MODEL="deepseek/deepseek-v4-flash"
   - MODEL_HAIKU=deepseek/deepseek-v4-flash
   - MODEL_SONNET / MODEL_OPUS = deepseek/deepseek-v4-pro
   - MESSAGING_PLATFORM="none", WHISPER_DEVICE="cpu"
3. Запусти fcc-server в фоне (порт 58082).
4. НЕ используй fcc-claude — OAuth токен из macOS keychain перебивает
   токен прокси и возвращает 401. Создай ~/.local/bin/claude-ds:

   #!/usr/bin/env bash
   set -e
   curl -sf http://127.0.0.1:58082/health >/dev/null || { echo "fcc-server не запущен"; exit 1; }
   unset ANTHROPIC_API_KEY ANTHROPIC_AUTH_TOKEN ANTHROPIC_MODEL
   export ANTHROPIC_API_KEY=freecc ANTHROPIC_BASE_URL=http://127.0.0.1:58082
   exec claude --bare --plugin-dir ~/free-claude-code/ds-plugin "$@"

   chmod +x и протестируй: claude-ds -p "тест".

   Важно: флаг --plugin-dir подгружает ds-plugin, в котором лежит
   команда /ds-balance (см. шаг 5). Если плагин не нужен — убери флаг.

5. Установи плагин /ds-balance (проверка баланса DeepSeek):

   Скопируй папку ds-plugin из этого репо в ~/free-claude-code:
   cp -r ds-plugin ~/free-claude-code/

   ИЛИ создай вручную:

   mkdir -p ~/free-claude-code/ds-plugin/skills/ds-balance
   mkdir -p ~/free-claude-code/ds-plugin/scripts

   ~/free-claude-code/ds-plugin/skills/ds-balance/SKILL.md:
   ---
   name: ds-balance
   description: Проверить баланс аккаунта DeepSeek API
   ---
   Выполни и покажи результат:
   ```bash
   python3 ~/free-claude-code/ds-plugin/scripts/ds-balance.py
   ```

   ~/free-claude-code/ds-plugin/scripts/ds-balance.py:
   см. файл в репо — чистая stdlib (urllib + json), никаких зависимостей.
   chmod +x ~/free-claude-code/ds-plugin/scripts/ds-balance.py

   Проверь: запусти claude-ds → набери /ds-balance
   Вывод:
   💰 DeepSeek Balance
   ━━━━━━━━━━━━━━━━━━━
   Status:      ✅ Available
   Currency:    USD
   Total:       $1.86
   Topped up:   $1.86
   Granted:     $0.00
   ━━━━━━━━━━━━━━━━━━━

   /ds-balance доступна ТОЛЬКО в claude-ds (флаг --plugin-dir только
   в обёртке). Обычный claude и другие проекты команду не видят.

Итог: claude — обычный OAuth, claude-ds — DeepSeek через прокси.
Модели DeepSeek называются именно v4-flash / v4-pro, не deepseek-chat.
