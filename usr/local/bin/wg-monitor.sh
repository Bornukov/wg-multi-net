#!/bin/bash
# wg-monitor.sh — генерирует портал с кнопками сетей и таблицей мониторинга

OUTPUT="/opt/wg-portal/index.html"
NAMES_FILE="/opt/wg-portal/names.json"
NETWORKS=("net1:10.197.1.0/24" "net2:10.197.2.0/24" "net3:10.197.3.0/24" "net4:10.197.4.0/24")
VOLUME_BASE="/var/lib/docker/volumes"

# Читаем .env
if [[ -f /opt/wg-manager/.env ]]; then
    source /opt/wg-manager/.env
fi
PORTAL_DOMAIN="${PORTAL_DOMAIN:-vpn1.example.com}"

declare -A DEFAULT_NAMES=(
    [net1]="Сеть 1"
    [net2]="Сеть 2"
    [net3]="Сеть 3"
    [net4]="Сеть 4"
)

# Читаем имена из JSON
declare -A NET_NAMES
for key in "${!DEFAULT_NAMES[@]}"; do
    NET_NAMES[$key]="${DEFAULT_NAMES[$key]}"
done

if [[ -f "$NAMES_FILE" ]]; then
    while IFS='=' read -r k v; do
        [[ -n "$k" && -n "$v" ]] && NET_NAMES[$k]="$v"
    done < <(python3 -c "
import json,sys
try:
    with open('$NAMES_FILE') as f:
        d = json.load(f)
    for k,v in d.items():
        print(f'{k}={v}')
except Exception:
    pass
")
fi

{
echo '<!DOCTYPE html>'
echo '<html lang="ru"><head><meta charset="UTF-8">'
echo '<meta name="viewport" content="width=device-width, initial-scale=1.0">'
echo '<meta http-equiv="refresh" content="60">'
echo '<title>Панель управления VPN</title>'
echo '<style>'
echo 'body{font-family:-apple-system,BlinkMacSystemFont,"Segoe UI",Roboto,Helvetica,Arial,sans-serif;background:#1a1a1a;color:#e0e0e0;margin:0;padding:20px;box-sizing:border-box;}'
echo '.container{max-width:1000px;margin:0 auto;background:#2a2a2a;padding:40px;border-radius:12px;box-shadow:0 10px 25px rgba(0,0,0,0.5);}'
echo 'h1{margin-top:0;font-weight:500;text-align:center;}'
echo 'h2{font-weight:500;margin-top:40px;margin-bottom:15px;color:#ccc;}'
echo '.hint{font-size:0.85em;color:#888;margin-bottom:25px;text-align:center;}'
echo '.net-grid{display:grid;grid-template-columns:1fr 1fr;gap:15px;}'
echo '.net-card{position:relative;background-color:#3a3a3a;border-radius:8px;border:1px solid #444;transition:background-color 0.2s,transform 0.1s;overflow:hidden;}'
echo '.net-card:hover{background-color:#404040;transform:translateY(-2px);}'
echo '.net-link{display:block;padding:20px;color:#fff;text-decoration:none;}'
echo '.net-link .name{display:block;font-size:1.2em;font-weight:600;margin-bottom:5px;word-break:break-word;}'
echo '.net-link .cidr{display:block;font-size:0.9em;color:#aaa;}'
echo '.edit-btn{position:absolute;top:8px;right:8px;background:transparent;border:none;color:#888;cursor:pointer;font-size:1em;padding:4px 6px;border-radius:4px;opacity:0;transition:opacity 0.2s,background-color 0.2s,color 0.2s;}'
echo '.net-card:hover .edit-btn{opacity:1;}'
echo '.edit-btn:hover{background-color:#555;color:#fff;}'
echo '.net{margin-bottom:20px;border:1px solid #444;border-radius:8px;overflow:hidden;}'
echo '.net-header{background:#3a3a3a;padding:12px 20px;font-weight:600;border-bottom:1px solid #444;}'
echo 'table{width:100%;border-collapse:collapse;}'
echo 'th,td{text-align:left;padding:10px 20px;border-bottom:1px solid #333;font-size:0.9em;}'
echo 'th{color:#888;font-weight:500;}'
echo 'tr:last-child td{border-bottom:none;}'
echo '.empty{padding:15px 20px;color:#666;font-style:italic;}'
echo '.toast{position:fixed;bottom:20px;left:50%;transform:translateX(-50%);background:#007aff;color:#fff;padding:10px 20px;border-radius:6px;font-size:0.9em;opacity:0;transition:opacity 0.3s;pointer-events:none;}'
echo '.toast.show{opacity:1;}'
echo '</style></head><body>'
echo '<div class="container">'
echo '<h1>Панель управления VPN</h1>'
echo '<div class="hint">Наведите на карточку и нажмите ✎, чтобы переименовать. Имена сохраняются на сервере.</div>'
echo '<div class="net-grid" id="netGrid"></div>'

echo '<h2>Активные подключения</h2>'
echo "<div class=\"hint\" style=\"text-align:left;\">Обновлено: $(date '+%Y-%m-%d %H:%M:%S') (автообновление каждые 60 сек)</div>"

for entry in "${NETWORKS[@]}"; do
    name="${entry%%:*}"
    cidr="${entry##*:}"
    display_name="${NET_NAMES[$name]}"
    container="wg-${name}"
    db_path="${VOLUME_BASE}/wg-${name}-data/_data/db.sqlite3"

    echo "<div class=\"net\">"
    echo "<div class=\"net-header\">${display_name} — ${cidr}</div>"

    if ! docker ps --format '{{.Names}}' | grep -q "^${container}$"; then
        echo '<div class="empty">Контейнер не запущен</div>'
        echo '</div>'
        continue
    fi

    if [[ ! -f "$db_path" ]]; then
        echo '<div class="empty">База данных не найдена</div>'
        echo '</div>'
        continue
    fi

    DEVICES=$(sqlite3 -separator '|' "$db_path" \
        "SELECT name, address FROM devices ORDER BY name;" 2>/dev/null)

    if [[ -z "$DEVICES" ]]; then
        echo '<div class="empty">Нет устройств</div>'
        echo '</div>'
        continue
    fi

    echo '<table>'
    echo '<tr><th>Имя устройства</th><th>IP-адрес</th></tr>'

    OLD_IFS="$IFS"
    IFS=$'\n'
    for line in $DEVICES; do
        IFS='|' read -r dev_name address <<< "$line"
        [[ -z "$dev_name" ]] && continue
        clean_ip=$(echo "$address" | awk -F'[,/]' '{print $1}')
        echo "<tr>"
        echo "<td><strong>${dev_name}</strong></td>"
        echo "<td>${clean_ip}</td>"
        echo "</tr>"
    done
    IFS="$OLD_IFS"

    echo '</table>'
    echo '</div>'
done

# === JS ===
echo '<div class="toast" id="toast">Сохранено</div>'
echo '<script>'
echo 'const NETWORKS = ['
first=1
for entry in "${NETWORKS[@]}"; do
    name="${entry%%:*}"
    cidr="${entry##*:}"
    [[ $first -eq 0 ]] && echo ','
    first=0
    echo -n "  { key: '${name}', url: 'https://${name}.${PORTAL_DOMAIN}', cidr: '${cidr}', defaultName: '${NET_NAMES[$name]}' }"
done
echo ''
echo '];'
echo 'let namesCache = {};'
echo 'function showToast(text){'
echo '  const t = document.getElementById("toast");'
echo '  t.textContent = text;'
echo '  t.classList.add("show");'
echo '  setTimeout(() => t.classList.remove("show"), 1500);'
echo '}'
echo 'async function loadNames(){'
echo '  try {'
echo '    const r = await fetch("/api/names", { cache: "no-store" });'
echo '    if (!r.ok) throw new Error("HTTP " + r.status);'
echo '    namesCache = await r.json();'
echo '  } catch(e) {'
echo '    console.error("Не удалось загрузить имена:", e);'
echo '    namesCache = {};'
echo '  }'
echo '}'
echo 'async function saveName(key, name){'
echo '  const r = await fetch("/api/names", {'
echo '    method: "POST",'
echo '    headers: { "Content-Type": "application/json" },'
echo '    body: JSON.stringify({ key: key, name: name })'
echo '  });'
echo '  if (!r.ok) throw new Error("HTTP " + r.status);'
echo '  return await r.json();'
echo '}'
echo 'function render(){'
echo '  const grid = document.getElementById("netGrid");'
echo '  grid.innerHTML = "";'
echo '  NETWORKS.forEach(net => {'
echo '    const name = namesCache[net.key] || net.defaultName;'
echo '    const card = document.createElement("div");'
echo '    card.className = "net-card";'
echo '    const link = document.createElement("a");'
echo '    link.className = "net-link";'
echo '    link.href = net.url;'
echo '    link.target = "_blank";'
echo '    link.innerHTML = `<span class="name"></span><span class="cidr"></span>`;'
echo '    link.querySelector(".name").textContent = name;'
echo '    link.querySelector(".cidr").textContent = net.cidr;'
echo '    const editBtn = document.createElement("button");'
echo '    editBtn.className = "edit-btn";'
echo '    editBtn.title = "Переименовать";'
echo '    editBtn.textContent = "✎";'
echo '    editBtn.addEventListener("click", async (e) => {'
echo '      e.preventDefault(); e.stopPropagation();'
echo '      const current = namesCache[net.key] || net.defaultName;'
echo '      const newName = prompt("Новое название для «" + current + "»:", current);'
echo '      if (newName === null) return;'
echo '      const trimmed = newName.trim();'
echo '      if (!trimmed) return;'
echo '      try {'
echo '        await saveName(net.key, trimmed);'
echo '        namesCache[net.key] = trimmed;'
echo '        render();'
echo '        showToast("Сохранено: " + trimmed);'
echo '      } catch(err) {'
echo '        showToast("Ошибка сохранения");'
echo '      }'
echo '    });'
echo '    card.appendChild(link);'
echo '    card.appendChild(editBtn);'
echo '    grid.appendChild(card);'
echo '  });'
echo '}'
echo 'loadNames().then(render);'
echo '</script>'

echo '</div></body></html>'
} > "$OUTPUT"

chmod 644 "$OUTPUT"