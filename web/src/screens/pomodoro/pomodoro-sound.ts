export const POMODORO_SOUND_OPTIONS = ["Clock Ticking", "Ocean Waves", "Rain", "Brown Noise", "Kitchen Timer", "Gong", "None"];

export function pomodoroSoundFrequency(name: string): number {
  switch (name) {
    case "Ocean Waves":
      return 180;
    case "Rain":
      return 320;
    case "Brown Noise":
      return 90;
    case "Kitchen Timer":
      return 1040;
    case "Gong":
      return 220;
    case "Clock Ticking":
    default:
      return 880;
  }
}

export function pomodoroSoundWaveType(name: string): OscillatorType {
  switch (name) {
    case "Ocean Waves":
    case "Gong":
      return "sine";
    case "Brown Noise":
      return "sawtooth";
    case "Rain":
      return "square";
    case "Clock Ticking":
    case "Kitchen Timer":
    default:
      return "triangle";
  }
}
