import router from '@ohos.router';
import { DEFAULT_START_ROUTE } from './RouteMap';
import { RouteConstants } from '../common/constants/RouteConstants';

export interface RouterParams {
  source?: string;
  notebookId?: string;
}

export class AppRouter {
  static push(routePath: string, params?: RouterParams): void {
    try {
      router.pushUrl({
        url: routePath,
        params: params
      });
    } catch (_error) {
    }
  }

  static replace(routePath: string, params?: RouterParams): void {
    try {
      router.replaceUrl({
        url: routePath,
        params: params
      });
    } catch (_error) {
    }
  }

  static back(): void {
    try {
      router.back();
    } catch (_error) {
    }
  }

  static goHome(): void {
    AppRouter.replace(RouteConstants.HOME);
  }

  static openNotebookList(): void {
    AppRouter.push(RouteConstants.NOTEBOOK_LIST);
  }

  static openEditor(params?: RouterParams): void {
    AppRouter.push(RouteConstants.EDITOR, params);
  }

  static getDefaultStartRoute(): string {
    return DEFAULT_START_ROUTE;
  }
}
