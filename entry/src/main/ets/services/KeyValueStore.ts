import common from '@ohos.app.ability.common';
import preferences from '@ohos.data.preferences';
import { formatError, shouldUseMemoryStore } from '../utils/ErrorUtils';

export interface KeyValueStore {
  get(key: string, defaultValue: preferences.ValueType): Promise<preferences.ValueType>;
  put(key: string, value: preferences.ValueType): Promise<void>;
  delete(key: string): Promise<void>;
  flush(): Promise<void>;
}

const MEMORY_STORES: Map<string, Map<string, preferences.ValueType>> = new Map();

class MemoryStore implements KeyValueStore {
  constructor(private name: string) {}

  async get(key: string, defaultValue: preferences.ValueType): Promise<preferences.ValueType> {
    const store = this.getStore();
    const value = store.get(key);
    return value === undefined ? defaultValue : value;
  }

  async put(key: string, value: preferences.ValueType): Promise<void> {
    this.getStore().set(key, value);
  }

  async delete(key: string): Promise<void> {
    this.getStore().delete(key);
  }

  async flush(): Promise<void> {}

  private getStore(): Map<string, preferences.ValueType> {
    let store = MEMORY_STORES.get(this.name);
    if (!store) {
      store = new Map<string, preferences.ValueType>();
      MEMORY_STORES.set(this.name, store);
    }
    return store;
  }
}

export async function openKeyValueStore(context: common.Context | undefined, name: string): Promise<KeyValueStore> {
  if (!context) {
    return new MemoryStore(name);
  }

  try {
    return (await preferences.getPreferences(context, name)) as KeyValueStore;
  } catch (error) {
    if (shouldUseMemoryStore(error)) {
      return new MemoryStore(name);
    }
    throw new Error(`Failed to open preferences store "${name}": ${formatError(error)}`);
  }
}
