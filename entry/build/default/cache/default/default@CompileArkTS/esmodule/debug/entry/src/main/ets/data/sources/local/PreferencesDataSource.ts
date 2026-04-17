import type common from "@ohos:app.ability.common";
import preferences from "@ohos:data.preferences";
import { StorageKeys } from "@bundle:com.example.hosn/entry/ets/common/constants/StorageKeys";
export class PreferencesDataSource {
    private preferencesInstance?: preferences.Preferences;
    constructor(private readonly context: common.Context) {
    }
    async getString(key: string, defaultValue: string): Promise<string> {
        try {
            const preference: preferences.Preferences = await this.getPreferencesInstance();
            const value: preferences.ValueType = await preference.get(key, defaultValue);
            if (typeof value === 'string') {
                return value;
            }
        }
        catch (_error) {
        }
        return defaultValue;
    }
    async putString(key: string, value: string): Promise<void> {
        try {
            const preference: preferences.Preferences = await this.getPreferencesInstance();
            await preference.put(key, value);
            await preference.flush();
        }
        catch (_error) {
        }
    }
    async delete(key: string): Promise<void> {
        try {
            const preference: preferences.Preferences = await this.getPreferencesInstance();
            await preference.delete(key);
            await preference.flush();
        }
        catch (_error) {
        }
    }
    private async getPreferencesInstance(): Promise<preferences.Preferences> {
        if (this.preferencesInstance !== undefined) {
            return this.preferencesInstance;
        }
        this.preferencesInstance = await preferences.getPreferences(this.context, StorageKeys.PREFERENCES_NAME);
        return this.preferencesInstance;
    }
}
