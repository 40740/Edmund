// @ts-check
import { defineConfig } from "astro/config";
import UnoCSS from "unocss/astro";

export default defineConfig({
  site: "https://i7t5.github.io",
  base: "/Edmund",
  integrations: [
    UnoCSS({
      injectReset: true,
    }),
  ],
});
