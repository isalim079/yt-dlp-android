/** Lightweight in-process counters for /metrics text exposition. */
export class Metrics {
  private readonly counters = new Map<string, number>();

  inc(name: string, by = 1): void {
    this.counters.set(name, (this.counters.get(name) ?? 0) + by);
  }

  set(name: string, value: number): void {
    this.counters.set(name, value);
  }

  toPrometheus(): string {
    const lines: string[] = [];
    for (const [name, value] of this.counters) {
      lines.push(`# TYPE ${name} counter`);
      lines.push(`${name} ${value}`);
    }
    return `${lines.join('\n')}\n`;
  }
}

export const metrics = new Metrics();
