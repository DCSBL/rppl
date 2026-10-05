import { defineConfig } from "astro/config";

// Served from the custom domain https://rppl.nl (see public/CNAME).
export default defineConfig({
  site: "https://rppl.nl",
  trailingSlash: "always",
});
