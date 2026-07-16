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
        sans: [
          {
            name: "Karla",
            weights: ["400", "500", "600", "700"],
            italic: false,
          },
        ],
        mono: ["IBM Plex Mono"],
      },
    }),
  ],
  theme: {
    colors: {
      ink: "#1d2421",
      quiet: "#66736d",
      line: "#dce5df",
      paper: "#fbfcf9",
      wash: "#f1f7f3",
      teal: {
        DEFAULT: "#168277",
        dark: "#0c5f58",
        soft: "#d7eee8",
      },
      clay: "#a75534",
    },
  },
});
