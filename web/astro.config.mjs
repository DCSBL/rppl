import { defineConfig } from "astro/config";

// Served from https://dcsbl.github.io/rppl/. Drop `base` once a custom domain is set.
export default defineConfig({
  site: "https://dcsbl.github.io",
  base: "/rppl",
  trailingSlash: "always",
});
