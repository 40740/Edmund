import presetIcons from "@unocss/preset-icons";
import presetUno from "@unocss/preset-uno";
import presetWebFonts from "@unocss/preset-web-fonts";
import { defineConfig } from "unocss";

export default defineConfig({
  presets: [
    presetUno(),
    presetIcons({
      extraProperties: {
        display: "inline-block",
        "vertical-align": "middle",
      },
    }),
    presetWebFonts({
      provider: "google",
      fonts: {
        mono: ["IBM Plex Mono"],
      },
    }),
  ],
  theme: {
    fontFamily: {
      sans: ["system-ui", "sans-serif"],
      serif: ['"Iowan Old Style"', "ui-serif", "Georgia", "serif"],
    },
    colors: {
      background: "var(--color-background)",
      surface: "var(--color-surface)",
      tertiary: {
        DEFAULT: "var(--color-tertiary)",
        soft: "#f8f8f8"
      },
      border: "var(--color-border)",
      text: "var(--color-text)",
      secondary: "var(--color-secondary)",
      primary: {
        DEFAULT: "var(--color-primary)",
        strong: "var(--color-primary-strong)"
      },
      link: {
        DEFAULT: "var(--color-link)",
        strong: "var(--color-link-strong)",
        soft: "var(--color-link-soft)",
      },
    },
  },
});
