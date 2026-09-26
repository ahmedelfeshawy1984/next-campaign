'use client';

import type { BoardTask } from '@/lib/family-love/types';

export default function BusStrip({ task }: { task: BoardTask }) {
  const total = task.stations.length;
  const progressPercent = total <= 1 ? 100 : Math.round((Math.min(task.current_station_index, total - 1) / (total - 1)) * 100);
  const isDone = task.status === 'done';

  return (
    <div>
      <div className="fl-strip">
        <div className="fl-strip__track" />
        <div className="fl-strip__progress" style={{ inlineSize: `${progressPercent}%` }} />
        <div className="fl-strip__row">
          {task.stations.map((station) => {
            const state =
              station.order_index < task.current_station_index
                ? 'done'
                : station.order_index === task.current_station_index && !isDone
                  ? 'current'
                  : station.order_index === task.current_station_index && isDone
                    ? 'done'
                    : 'upcoming';
            return (
              <div className="fl-strip__stop" key={station.order_index}>
                <div className={`fl-strip__dot fl-strip__dot--${state}`}>{station.icon ?? '📍'}</div>
                <div className={`fl-strip__label ${state === 'current' ? 'fl-strip__label--current' : ''}`}>
                  {station.title}
                </div>
              </div>
            );
          })}
        </div>
      </div>
      <div className="fl__now">
        {isDone
          ? `وصل بالسلامة! 🎉`
          : `المحطة الحالية: ${task.stations[task.current_station_index]?.title ?? '—'}`}
      </div>
    </div>
  );
}
