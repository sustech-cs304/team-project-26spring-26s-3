import { DEFAULT_START_ROUTE, ROUTE_MAP } from './RouteMap';

export interface AppBootstrapState {
  isInitialized: boolean;
  startRoute: string;
  registeredRouteCount: number;
}

export class AppInitializer {
  private static initialized: boolean = false;

  private static bootstrapState: AppBootstrapState = {
    isInitialized: false,
    startRoute: DEFAULT_START_ROUTE,
    registeredRouteCount: 0
  };

  static initialize(): AppBootstrapState {
    if (AppInitializer.initialized) {
      return AppInitializer.bootstrapState;
    }

    AppInitializer.initialized = true;
    AppInitializer.bootstrapState = {
      isInitialized: true,
      startRoute: DEFAULT_START_ROUTE,
      registeredRouteCount: ROUTE_MAP.length
    };

    return AppInitializer.bootstrapState;
  }

  static getState(): AppBootstrapState {
    return AppInitializer.bootstrapState;
  }
}
