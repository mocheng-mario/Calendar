// Calendar 内置主题 · 二十四节气和九个节日
// 调整下方规则可以更换配色、图标和动效。

// 每套配色依次列出浅色和深色的渐变起点、渐变终点、文字色和动效色。
const themeColors = {
  spring: ["#EFFAF4", "#D9EEDF", "#206346", "#368660", "#142B24", "#203D31", "#A5E4C0", "#69CB99"],
  rain: ["#F0F8FC", "#D8E9F1", "#275D72", "#4E8DA4", "#152A35", "#213B48", "#AEDDEB", "#7AC8DE"],
  summer: ["#F0FAF9", "#D2EEEA", "#1C655D", "#2F8980", "#112B30", "#1B4144", "#A7E9D9", "#60D6C2"],
  harvest: ["#FFFAE9", "#F5E9BF", "#735510", "#AB7F25", "#30281A", "#483B24", "#F5DB94", "#E6B85D"],
  heat: ["#FFF5EA", "#F9DFC4", "#8A4223", "#D77B34", "#332418", "#4B3023", "#FFC496", "#FFAB65"],
  autumn: ["#FFF5E9", "#F2DEC9", "#804B2A", "#B96C3F", "#30231D", "#473229", "#F2C7A0", "#E7A26C"],
  winter: ["#F0F9FF", "#D5E7F3", "#285677", "#5383A7", "#142639", "#20394F", "#B6DEFB", "#D9F1FF"],
  festival: ["#FFF2EF", "#F8D9D0", "#9A342F", "#D17C3E", "#372127", "#502C2D", "#FFBCAD", "#FFD48B"],
  moon: ["#F6F2FC", "#E3DDF4", "#5F4D8E", "#9A71A3", "#22223B", "#35324D", "#DFCCFF", "#FFE5AB"]
};

const fullTurn = Math.PI * 2;

function sample(index, salt) {
  return ((index * 31 + salt * 17) % 97) / 97;
}

function dot(ctx, x, y, radius) {
  ctx.beginPath();
  ctx.arc(x, y, radius, 0, fullTurn);
  ctx.fill();
}

function drift(shape, count, speed, wind) {
  return ({ ctx, width, height, time }, accent) => {
    const unit = Math.min(width, height) / 48;
    ctx.fillStyle = accent;
    ctx.strokeStyle = accent;

    for (let i = 0; i < count; i++) {
      const phase = (time * speed * (0.7 + sample(i, 4) * 0.6) + sample(i, 2)) % 1;
      const x = ((sample(i, 7) + phase * wind + Math.sin(phase * fullTurn + i) * 0.025 + 1) % 1) * width;
      const y = (shape === "glow" ? 1 - phase : phase) * height;
      const radius = (0.6 + sample(i, 3) * 1.2) * unit;
      ctx.globalAlpha = Math.sin(phase * Math.PI) * (0.25 + sample(i, 5) * 0.42);

      if (shape === "rain") {
        ctx.lineWidth = 0.75 * unit;
        ctx.beginPath();
        ctx.moveTo(x, y);
        ctx.lineTo(x + wind * 12 * unit, y + (3 + sample(i, 1) * 5) * unit);
        ctx.stroke();
      } else if (shape === "leaf" || shape === "petal") {
        ctx.beginPath();
        ctx.ellipse(x, y, radius * 1.55, radius * 0.65, phase * fullTurn + i, 0, fullTurn);
        ctx.fill();
      } else {
        dot(ctx, x, y, radius);
        if (shape === "snow" && i % 5 === 0) {
          ctx.lineWidth = 0.55 * unit;
          ctx.beginPath();
          ctx.moveTo(x - radius * 1.7, y);
          ctx.lineTo(x + radius * 1.7, y);
          ctx.moveTo(x, y - radius * 1.7);
          ctx.lineTo(x, y + radius * 1.7);
          ctx.stroke();
        }
      }
    }
  };
}

function waves(count, speed, amplitude) {
  return ({ ctx, width, height, time }, accent) => {
    ctx.strokeStyle = accent;
    ctx.lineWidth = Math.min(width, height) * 0.016;
    for (let band = 0; band < count; band++) {
      const level = height * (0.18 + band * 0.64 / Math.max(1, count - 1));
      ctx.globalAlpha = 0.23 + band * 0.06;
      ctx.beginPath();
      for (let i = 0; i <= 14; i++) {
        const x = width * i / 14;
        const y = level + Math.sin(i * 0.39 + time * speed + band * 1.7) * height * amplitude;
        if (i === 0) ctx.moveTo(x, y);
        else ctx.lineTo(x, y);
      }
      ctx.stroke();
    }
  };
}

function ripples(count, speed) {
  return ({ ctx, width, height, time }, accent) => {
    const unit = Math.min(width, height);
    ctx.strokeStyle = accent;
    ctx.lineWidth = unit * 0.018;
    for (let i = 0; i < count; i++) {
      const phase = (time * speed + sample(i, 3)) % 1;
      const x = width * sample(i, 1);
      const y = height * (0.25 + sample(i, 5) * 0.7);
      const radius = unit * (0.025 + phase * 0.16);
      ctx.globalAlpha = (1 - phase) * 0.44;
      ctx.beginPath();
      ctx.ellipse(x, y, radius * 1.35, radius * 0.65, 0, 0, fullTurn);
      ctx.stroke();
    }
  };
}

function glowAt(xRatio, yRatio, radiusRatio, speed) {
  return ({ ctx, width, height, time }, accent) => {
    const unit = Math.min(width, height);
    const x = width * xRatio + Math.sin(time * speed) * width * 0.04;
    const y = height * yRatio + Math.sin(time * speed * 0.7) * height * 0.04;
    const radius = unit * radiusRatio;
    const halo = ctx.createRadialGradient(x, y, radius * 0.35, x, y, radius * 2.2);
    halo.addColorStop(0, accent);
    halo.addColorStop(1, "transparent");
    ctx.globalAlpha = 0.5;
    ctx.fillStyle = halo;
    dot(ctx, x, y, radius * 2.2);
    ctx.globalAlpha = 0.38;
    ctx.fillStyle = accent;
    dot(ctx, x, y, radius);
  };
}

function lanterns(count, speed) {
  return ({ ctx, width, height, time }, accent) => {
    const unit = Math.min(width, height);
    ctx.fillStyle = accent;
    ctx.strokeStyle = accent;
    ctx.lineWidth = unit * 0.016;
    for (let i = 0; i < count; i++) {
      const x = width * ((i + 0.5) / count + Math.sin(time * speed + i) * 0.035);
      const y = height * (0.26 + sample(i, 8) * 0.23 + Math.sin(time * speed + i) * 0.04);
      const radius = unit * (0.07 + sample(i, 2) * 0.025);
      ctx.globalAlpha = 0.45 + Math.sin(time * speed * 1.6 + i) * 0.12;
      ctx.beginPath();
      ctx.moveTo(x, 0);
      ctx.lineTo(x, y - radius);
      ctx.moveTo(x, y + radius);
      ctx.lineTo(x, y + radius * 1.5);
      ctx.stroke();
      ctx.beginPath();
      ctx.ellipse(x, y, radius, radius * 0.84, 0, 0, fullTurn);
      ctx.fill();
    }
  };
}

function fireworks(count, rays, speed) {
  return ({ ctx, width, height, time }, accent) => {
    const unit = Math.min(width, height);
    ctx.fillStyle = accent;
    for (let i = 0; i < count; i++) {
      const phase = (time * speed + i / count) % 1;
      const x = width * (0.18 + sample(i, 1) * 0.66);
      const y = height * (0.18 + sample(i, 4) * 0.58);
      const radius = unit * (0.045 + phase * 0.23);
      ctx.globalAlpha = Math.sin(phase * Math.PI) * 0.66;
      for (let j = 0; j < rays; j++) {
        const angle = j / rays * fullTurn + i;
        dot(ctx, x + Math.cos(angle) * radius, y + Math.sin(angle) * radius, unit * 0.022);
      }
    }
  };
}

function theme({ appearance }) {
  const dark = appearance === "dark";

  function style(palette, icon, ...effects) {
    const colors = themeColors[palette];
    const offset = dark ? 4 : 0;
    const [top, bottom, ink, accent] = colors.slice(offset, offset + 4);

    return {
      cell: {
        subtitleColor: ink,
        background: frame => {
          const { ctx, width, height } = frame;
          const gradient = ctx.createLinearGradient(0, 0, width * 0.35, height);
          gradient.addColorStop(0, top);
          gradient.addColorStop(1, bottom);
          ctx.fillStyle = gradient;
          ctx.fillRect(0, 0, width, height);
          for (const effect of effects) {
            ctx.save();
            effect(frame, accent);
            ctx.restore();
          }
        }
      },
      badge: { icon, color: ink }
    };
  }

  return {
    version: 1,
    festivals: {
      newYearsDay: style("moon", "sparkles", fireworks(3, 8, 0.45)),
      springFestival: style("festival", "sparkles", fireworks(3, 10, 0.42), drift("glow", 6, 0.20, 0.12)),
      springFestivalEve: style("festival", "flame.fill", lanterns(3, 1.1), drift("glow", 5, 0.12, 0.08)),
      lanternFestival: style("festival", "sparkles", lanterns(5, 1.5)),
      qingming: style("rain", "cloud.rain", drift("rain", 10, 0.34, 0.14)),
      laborDay: style("spring", "leaf.fill", drift("leaf", 8, 0.14, 0.35), waves(2, 0.8, 0.03)),
      dragonBoatFestival: style("summer", "leaf.fill", waves(3, 2.3, 0.07), drift("leaf", 5, 0.15, 0.38)),
      midAutumnFestival: style("moon", "moon.stars.fill", glowAt(0.74, 0.34, 0.14, 0.5), drift("glow", 7, 0.09, 0.08)),
      nationalDay: style("festival", "flag.fill", fireworks(4, 9, 0.32), waves(2, 1.1, 0.04))
    },
    solarTerms: {
      minorCold: style("winter", "snowflake", drift("snow", 11, 0.14, 0.09)),
      majorCold: style("winter", "wind", drift("snow", 16, 0.17, 0.29), waves(2, 1.2, 0.045)),
      startOfSpring: style("spring", "leaf", drift("leaf", 7, 0.095, 0.14)),
      rainWater: style("rain", "drop", drift("rain", 12, 0.40, 0.10), ripples(3, 0.55)),
      awakeningOfInsects: style("spring", "bolt.fill", drift("glow", 12, 0.18, 0.24)),
      springEquinox: style("spring", "sun.max", drift("petal", 11, 0.13, 0.27)),
      qingming: style("rain", "cloud.rain", drift("rain", 10, 0.34, 0.14)),
      grainRain: style("harvest", "cloud.rain", drift("rain", 8, 0.39, 0.15), drift("leaf", 5, 0.12, 0.22)),
      startOfSummer: style("summer", "sun.max", glowAt(0.80, 0.22, 0.10, 0.85), waves(2, 1.5, 0.045)),
      grainFull: style("harvest", "leaf", drift("leaf", 10, 0.09, 0.20)),
      grainInEar: style("harvest", "leaf.fill", drift("petal", 12, 0.15, 0.32), waves(2, 1.25, 0.06)),
      summerSolstice: style("heat", "sun.max", glowAt(0.73, 0.25, 0.17, 0.6), waves(2, 1.6, 0.04)),
      minorHeat: style("heat", "sun.max", waves(3, 1.35, 0.06)),
      majorHeat: style("heat", "flame.fill", glowAt(0.79, 0.29, 0.18, 0.95), drift("glow", 10, 0.19, 0.09)),
      startOfAutumn: style("autumn", "leaf", drift("leaf", 9, 0.12, 0.32)),
      endOfHeat: style("summer", "wind", waves(3, 1.7, 0.05), drift("leaf", 4, 0.085, 0.4)),
      whiteDew: style("rain", "drop", ripples(6, 0.33), drift("glow", 5, 0.09, 0.09)),
      autumnEquinox: style("autumn", "leaf.fill", drift("leaf", 14, 0.15, 0.22)),
      coldDew: style("rain", "drop", waves(2, 0.7, 0.035), ripples(4, 0.40)),
      frostDescent: style("winter", "sparkles", drift("snow", 13, 0.075, 0.13)),
      startOfWinter: style("winter", "wind", waves(3, 1.3, 0.035), drift("snow", 6, 0.12, 0.25)),
      xiaoxue: style("winter", "snowflake", drift("snow", 9, 0.13, 0.11)),
      majorSnow: style("winter", "snowflake", drift("snow", 23, 0.18, 0.28), drift("snow", 6, 0.29, 0.35)),
      winterSolstice: style("moon", "sun.max", glowAt(0.75, 0.67, 0.14, 0.55), drift("snow", 8, 0.10, 0.10))
    },
    schedules: [
      // 在此插入日程规则
    ]
  };
}
