'use client';

import { useState, useEffect, useRef } from 'react';

interface SearchBarProps {
  onSearch: (query: string) => void;
  placeholder?: string;
  initialValue?: string;
  large?: boolean;
}

export default function SearchBar({ onSearch, placeholder = 'Rechercher...', initialValue = '', large = false }: SearchBarProps) {
  const [value, setValue] = useState(initialValue);
  const timerRef = useRef<ReturnType<typeof setTimeout> | null>(null);

  useEffect(() => {
    setValue(initialValue);
  }, [initialValue]);

  const handleChange = (e: React.ChangeEvent<HTMLInputElement>) => {
    const newValue = e.target.value;
    setValue(newValue);

    if (timerRef.current) clearTimeout(timerRef.current);
    timerRef.current = setTimeout(() => {
      onSearch(newValue);
    }, 300);
  };

  const handleClear = () => {
    setValue('');
    onSearch('');
  };

  const handleKeyDown = (e: React.KeyboardEvent) => {
    if (e.key === 'Enter') {
      if (timerRef.current) clearTimeout(timerRef.current);
      onSearch(value);
    }
  };

  return (
    <div className="relative w-full">
      {/* Search icon */}
      <div className={`absolute left-3 top-1/2 -translate-y-1/2 text-[#6b7280] pointer-events-none ${large ? 'left-4' : ''}`}>
        <svg width={large ? '20' : '16'} height={large ? '20' : '16'} viewBox="0 0 20 20" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round">
          <circle cx="9" cy="9" r="6" />
          <path d="M13.5 13.5L17 17" />
        </svg>
      </div>

      <input
        type="text"
        value={value}
        onChange={handleChange}
        onKeyDown={handleKeyDown}
        placeholder={placeholder}
        className={`w-full bg-white border border-beige-300 rounded-xl text-[#1a1a1a] placeholder-[#6b7280] focus:outline-none focus:ring-2 focus:ring-accent/30 focus:border-accent transition-colors ${
          large
            ? 'pl-12 pr-10 py-3.5 text-base'
            : 'pl-9 pr-9 py-2.5 text-sm'
        }`}
      />

      {/* Clear button */}
      {value && (
        <button
          onClick={handleClear}
          className={`absolute top-1/2 -translate-y-1/2 text-[#6b7280] hover:text-[#1a1a1a] transition-colors ${
            large ? 'right-4' : 'right-3'
          }`}
        >
          <svg width="16" height="16" viewBox="0 0 16 16" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round">
            <path d="M4 4L12 12" />
            <path d="M12 4L4 12" />
          </svg>
        </button>
      )}
    </div>
  );
}
