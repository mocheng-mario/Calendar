(() => {
    "use strict";

    const canvas = document.querySelector("canvas");
    const context = canvas.getContext("2d");
    const appearances = ["light", "dark"];
    const surfaces = { light: "#FFFFFF", dark: "#2B2D32" };
    const maximumScheduleRules = 100;
    const frameInterval = 1000 / 30;
    const previewDuration = 1000;

    let painters = new Map();
    let pendingPainters = null;
    let scene = null;
    let sceneID = null;
    let tiles = [];
    let frame = 0;
    let start = null;
    let lastFrame = -Infinity;
    let nextHeartbeat = -Infinity;
    let rendering = false;
    let previewStarted = null;
    let previewPassed = false;

    function emit(kind, detail = {}) {
        window.webkit?.messageHandlers?.calendarThemeEvent?.postMessage({ sceneID, kind, ...detail });
    }

    function object(value, path, keys) {
        if (value === null || typeof value !== "object" || Array.isArray(value)) {
            throw new Error(path + " 必须是对象。");
        }
        for (const key of Object.keys(value)) {
            if (!keys.includes(key)) throw new Error(path + " 包含未知字段 " + key + "。");
        }
        return value;
    }

    function themeColor(value, path) {
        if (value === undefined) return undefined;
        if (typeof value === "string" && /^#[0-9a-f]{6}$/i.test(value)) return value;
        throw new Error(path + " 需要 #RRGGBB 颜色。");
    }

    function background(value, path, key, callbacks) {
        if (value === undefined) return undefined;
        if (typeof value === "string") return { color: themeColor(value, path) };
        if (typeof value === "function") {
            callbacks.set(key, value);
            return { painter: key };
        }
        throw new Error(path + " 需要 #RRGGBB 颜色或绘图函数。");
    }

    function decoration(value, path, colorField) {
        if (value === undefined) return undefined;
        object(value, path, [colorField, "icon"]);
        const icon = value.icon;
        if (icon !== undefined && (typeof icon !== "string" || !icon.trim() || icon.length > 100)) {
            throw new Error(path + ".icon 需要填写系统图标名称。");
        }
        return { [colorField]: themeColor(value[colorField], path + "." + colorField), icon };
    }

    function occasionStyle(style, path, key, callbacks) {
        object(style, path, ["cell", "badge"]);
        const cell = style.cell === undefined ? {} : object(style.cell, path + ".cell", ["background", "subtitleColor"]);
        return {
            background: background(cell.background, path + ".cell.background", key, callbacks),
            subtitleColor: themeColor(cell.subtitleColor, path + ".cell.subtitleColor"),
            badge: decoration(style.badge, path + ".badge", "color")
        };
    }

    function scheduleMatch(value, path) {
        object(value, path, ["id", "titleEquals", "titleContains"]);
        const keys = Object.keys(value);
        if (keys.length !== 1) throw new Error(path + " 需要指定一种日程匹配方式。");
        const key = keys[0];
        const text = value[key];
        if (typeof text !== "string" || !text.trim() || text.length > 512) {
            throw new Error(path + "." + key + " 需要填写有效文本。");
        }
        if (key === "id" && !/^[0-9a-f]{8}-(?:[0-9a-f]{4}-){3}[0-9a-f]{12}$/i.test(text)) {
            throw new Error(path + ".id 需要有效的 UUID。");
        }
        return { [key]: text };
    }

    function invoke(paint, ctx, width, height, time, appearance) {
        const result = paint({ ctx, width, height, time, appearance });
        if (result && typeof result.then === "function") {
            throw new Error("背景绘图函数需要同步完成。");
        }
    }

    function load(source, validate, festivalIDs, solarTermIDs) {
        if (!source.trim()) throw new Error("请输入主题脚本。");
        const theme = new Function('"use strict";\n' + source + '\n;return typeof theme === "function" ? theme : null;')();
        if (!theme) throw new Error("请定义 function theme({ appearance })。");

        const callbacks = new Map();
        const manifest = {};

        for (const appearance of appearances) {
            const rules = object(theme({ appearance }), "theme()", ["version", "festivals", "solarTerms", "schedules"]);
            if (rules.version !== 1) throw new Error("theme().version 必须为 1。");
            const entries = { festivals: {}, solarTerms: {}, schedules: [] };
            for (const [group, ids] of [["festivals", festivalIDs], ["solarTerms", solarTermIDs]]) {
                if (rules[group] === undefined) continue;
                const styles = object(rules[group], group, ids);
                for (const [id, style] of Object.entries(styles)) {
                    const path = group + "." + id;
                    entries[group][id] = occasionStyle(style, path, appearance + "." + path, callbacks);
                }
            }

            const schedules = rules.schedules === undefined ? [] : rules.schedules;
            if (!Array.isArray(schedules) || schedules.length > maximumScheduleRules) {
                throw new Error("schedules 需要是最多 " + maximumScheduleRules + " 条规则的数组。");
            }
            const occurrences = new Map();
            for (const [index, entry] of schedules.entries()) {
                const path = "schedules[" + index + "]";
                object(entry, path, ["match", "cell", "dotColor", "row"]);
                const cell = entry.cell === undefined ? {} : object(entry.cell, path + ".cell", ["background"]);
                const match = scheduleMatch(entry.match, path + ".match");
                const [[type, text]] = Object.entries(match);
                const key = type + ":" + (type === "id" ? text.toLowerCase() : text.normalize("NFC"));
                const occurrence = occurrences.get(key) ?? 0;
                occurrences.set(key, occurrence + 1);
                entries.schedules.push({
                    match,
                    background: background(cell.background, path + ".cell.background",
                                           appearance + ".schedule." + key + "#" + occurrence, callbacks),
                    dotColor: themeColor(entry.dotColor, path + ".dotColor"),
                    row: decoration(entry.row, path + ".row", "titleColor")
                });
            }
            manifest[appearance] = entries;
        }

        if (validate) {
            const sample = document.createElement("canvas");
            for (const [key, paint] of callbacks) {
                const appearance = key.startsWith("light.") ? "light" : "dark";
                try {
                    for (const time of [0, 0.5]) {
                        sample.width = 96;
                        sample.height = 66;
                        invoke(paint, sample.getContext("2d"), 96, 66, time, appearance);
                    }
                } catch (error) {
                    throw new Error(key + " 绘制失败：" + error);
                }
            }
        }
        if (!validate) pendingPainters = callbacks;
        return JSON.stringify(manifest);
    }

    function show(nextScene, id) {
        // Swift checks the new rule list before allowing it to replace the active painters.
        if (pendingPainters !== null) {
            painters = pendingPainters;
            pendingPainters = null;
        }
        const keepTime = scene && scene.isDark === nextScene.isDark && scene.reduceMotion === nextScene.reduceMotion;
        scene = nextScene;
        sceneID = id;
        rendering = false;
        nextHeartbeat = -Infinity;
        previewStarted = null;
        previewPassed = false;
        const appearance = scene.isDark ? "dark" : "light";
        document.documentElement.style.backgroundColor = surfaces[appearance];
        document.body.style.backgroundColor = surfaces[appearance];
        tiles = scene.tiles.map(tile => ({ ...tile, buffer: document.createElement("canvas"), failed: false }));
        stop();
        if (!keepTime) start = null;
        lastFrame = -Infinity;
        draw(performance.now());
    }

    function resetBuffer(tile, scale) {
        const width = Math.max(1, Math.ceil(tile.width * scale));
        const height = Math.max(1, Math.ceil(tile.height * scale));
        if (tile.buffer.width !== width || tile.buffer.height !== height) {
            tile.buffer.width = width;
            tile.buffer.height = height;
        } else if (typeof tile.buffer.getContext("2d").reset === "function") {
            tile.buffer.getContext("2d").reset();
        } else {
            tile.buffer.width = width;
        }
        const ctx = tile.buffer.getContext("2d");
        ctx.setTransform(scale, 0, 0, scale, 0, 0);
        return ctx;
    }

    function renderTile(tile, scale, time, appearance) {
        if (tile.failed || tile.width <= 0 || tile.height <= 0) return;
        try {
            const paint = painters.get(tile.painter);
            if (!paint) throw new Error("找不到背景绘图函数。");
            const ctx = resetBuffer(tile, scale);
            invoke(paint, ctx, tile.width, tile.height, time, appearance);
            // Each callback draws in its own buffer so transforms and clipping stay local.
            context.save();
            try {
                // Check composition for every preview tile while displaying only the selected one.
                if (scene.previewTileID != null && tile.id !== scene.previewTileID) context.globalAlpha = 0;
                context.translate(tile.x, tile.y);
                context.beginPath();
                const radius = Math.min(7, tile.width / 2, tile.height / 2);
                if (typeof context.roundRect === "function") {
                    context.roundRect(0, 0, tile.width, tile.height, radius);
                } else {
                    const { width: w, height: h } = tile;
                    context.moveTo(radius, 0);
                    context.arcTo(w, 0, w, h, radius);
                    context.arcTo(w, h, 0, h, radius);
                    context.arcTo(0, h, 0, 0, radius);
                    context.arcTo(0, 0, w, 0, radius);
                    context.closePath();
                }
                context.clip();
                context.drawImage(tile.buffer, 0, 0, tile.buffer.width / scale, tile.buffer.height / scale);
            } finally {
                context.restore();
            }
        } catch (error) {
            tile.failed = true;
            emit("error", { tileID: tile.id, painter: tile.painter, message: String(error).slice(0, 500) });
        }
    }

    function idle() {
        if (rendering) emit("idle");
        rendering = false;
        nextHeartbeat = -Infinity;
    }

    function draw(now) {
        frame = 0;
        if (!scene || document.hidden) {
            idle();
            previewStarted = null;
            return;
        }
        if (start === null) start = now;
        if (now - lastFrame >= frameInterval - 1) {
            if (now >= nextHeartbeat) {
                emit("frame");
                rendering = true;
                nextHeartbeat = now + 1000;
            }
            const scale = Math.min(window.devicePixelRatio || 1, 2);
            const width = Math.max(1, Math.ceil(canvas.clientWidth * scale));
            const height = Math.max(1, Math.ceil(canvas.clientHeight * scale));
            if (canvas.width !== width || canvas.height !== height) {
                canvas.width = width;
                canvas.height = height;
            }
            context.setTransform(scale, 0, 0, scale, 0, 0);
            context.clearRect(0, 0, width / scale, height / scale);
            const time = scene.reduceMotion ? 0 : (now - start) / 1000;
            const appearance = scene.isDark ? "dark" : "light";
            for (const tile of tiles) renderTile(tile, scale, time, appearance);
            if (scene.previewTileID != null && !previewPassed) {
                if (previewStarted === null) previewStarted = now;
                if ((scene.reduceMotion || now - previewStarted >= previewDuration) &&
                    tiles.length > 0 && tiles.every(tile => !tile.failed && tile.width > 0 && tile.height > 0)) {
                    previewPassed = true;
                    emit("previewPassed");
                }
            }
            lastFrame = now;
        }
        if (!scene.reduceMotion && tiles.some(tile => !tile.failed)) {
            frame = requestAnimationFrame(draw);
        } else {
            idle();
        }
    }

    function stop() {
        if (frame) cancelAnimationFrame(frame);
        frame = 0;
    }

    function repaint() {
        if (!scene) return;
        stop();
        lastFrame = -Infinity;
        draw(performance.now());
    }

    window.addEventListener("resize", repaint);
    document.addEventListener("visibilitychange", repaint);
    Object.defineProperty(window, "calendarThemeCanvas", { value: Object.freeze({ load, show }) });
})();
