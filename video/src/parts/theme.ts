import { loadFont } from "@remotion/google-fonts/NotoSansJP";

// Noto Sans JP(SIL Open Font License 1.1)
export const { fontFamily } = loadFont("normal", {
  weights: ["400", "700", "900"],
  subsets: ["japanese", "latin"],
});

export const C = {
  bg: "#F6F3EE",
  ink: "#1C1C1E",
  sub: "#5B5B60",
  line: "#D9D4CC",
  red: "#D7363B",
  redSoft: "#FBE3E3",
  blue: "#0A6CF0",
  blueSoft: "#DCEBFF",
  dark: "#16171B",
  card: "#FFFFFF",
} as const;
