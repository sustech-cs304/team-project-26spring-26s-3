import { RouteConstants } from "@bundle:com.example.hosn/entry/ets/common/constants/RouteConstants";
export interface RouteDefinition {
    key: string;
    path: string;
}
export interface RouteNameMap {
    index: string;
    home: string;
    notebookList: string;
    editor: string;
}
export const ROUTE_MAP: RouteDefinition[] = [
    { key: 'index', path: RouteConstants.INDEX },
    { key: 'home', path: RouteConstants.HOME },
    { key: 'notebookList', path: RouteConstants.NOTEBOOK_LIST },
    { key: 'editor', path: RouteConstants.EDITOR }
];
export const ROUTE_NAME_MAP: RouteNameMap = {
    index: RouteConstants.INDEX,
    home: RouteConstants.HOME,
    notebookList: RouteConstants.NOTEBOOK_LIST,
    editor: RouteConstants.EDITOR
};
export const DEFAULT_START_ROUTE: string = ROUTE_NAME_MAP.home;
