// @ts-check
import { defineConfig } from "astro/config";
import UnoCSS from "unocss/astro";

export default defineConfig({
  site: "https://edmund.md",
  base: "/",
  integrations: [
    UnoCSS({
      injectReset: true,
    }),
  ],
});
