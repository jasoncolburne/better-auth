import { defineConfig } from "tsup";

export default defineConfig({
  entry: ["src/entry.ts"],
  format: ["esm"],
  target: "es2022",
  platform: "browser",
  sourcemap: true,
  clean: true,
  dts: true,
  outDir: "dist",
  noExternal: ["better-auth-ts", "@noble/hashes/blake3.js"]
});
