import type { Caption } from "./CapturePreview";

// Seconds into public/capture/ipad.mp4; boundaries come from the segment list the cut was made with.
export const IPAD_CAPTIONS: Caption[] = [
  { text: "Start from a template", from: 0.15, to: 3.05 },
  { text: "Add your app’s screenshots", from: 3.2, to: 8.1 },
  { text: "Restyle a whole row in one tap", from: 8.3, to: 12.3 },
  { text: "Translate your captions", from: 12.5, to: 20.7 },
  { text: "Every screenshot, every language", from: 20.9, to: 26.1 },
];

// Seconds into public/capture/iphone.mp4.
export const IPHONE_CAPTIONS: Caption[] = [
  { text: "Start from a template", from: 0.15, to: 2.85 },
  { text: "Add your app’s screenshots", from: 3.0, to: 7.1 },
  { text: "Restyle a whole row in one tap", from: 7.25, to: 12.95 },
  { text: "Translate your captions", from: 13.1, to: 21.75 },
  { text: "Every screenshot, every language", from: 21.95, to: 26.85 },
];

// Seconds into public/capture/mac.mp4.
export const MAC_CAPTIONS: Caption[] = [
  { text: "Start from a template", from: 0.15, to: 2.6 },
  { text: "Add your app’s screenshots", from: 2.75, to: 8.3 },
  { text: "Restyle a whole row in one click", from: 8.45, to: 14.85 },
  { text: "Translate your captions", from: 15.0, to: 22.3 },
  { text: "Every screenshot, every language", from: 22.45, to: 27.7 },
];
