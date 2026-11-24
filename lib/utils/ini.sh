#!/hint/bash

[[ -n "${__UTILS_INI_SH_LOADED:-}" ]] && return 0
__UTILS_INI_SH_LOADED=1

# 从 stdin 读取 ini 文本，按参数顺序每行输出一个 key 的值；未找到的 key 输出空行
# 用法: ini_get <key>... < file
ini_get() {
    local sep=$'\x1f' keys
    printf -v keys "%s$sep" "$@"          # 每个 key 后带一个分隔符

    awk -v keys="$keys" -v sep="$sep" '
        BEGIN {
            t = split(keys, T, sep)
            n = 0
            for (i = 1; i <= t; i++)           # 过滤尾部空串
                if (T[i] != "") { K[++n] = T[i]; want[T[i]] = n }
        }
        /^[ \t]*[;#]/ { next }
        {
            line = $0
            sub(/\r$/, "", line)
            eq = index(line, "=");  if (!eq) next
            k = substr(line, 1, eq - 1)
            v = substr(line, eq + 1)
            gsub(/^[ \t]+|[ \t]+$/, "", k)
            gsub(/^[ \t]+|[ \t]+$/, "", v)
            if (k in want) val[want[k]] = v    # 同名后写覆盖前写
        }
        END { for (i = 1; i <= n; i++) print (i in val ? val[i] : "") }
    '
}
