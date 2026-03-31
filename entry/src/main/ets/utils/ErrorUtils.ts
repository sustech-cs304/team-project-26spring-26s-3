type ErrorValue = Object | string | number | boolean | undefined | null;
type ErrorRecordValue = Object | string | number | boolean | undefined | null;
type ErrorRecord = Record<string, ErrorRecordValue>;

function asErrorRecord(error: ErrorValue): ErrorRecord | undefined {
  if (!error || typeof error === 'string' || typeof error === 'number' || typeof error === 'boolean') {
    return undefined;
  }
  return error as ErrorRecord;
}

export function getErrorCode(error: ErrorValue): number | undefined {
  const record = asErrorRecord(error);
  const code = record?.code;
  return typeof code === 'number' ? code : undefined;
}

export function formatError(error: ErrorValue): string {
  if (error === undefined || error === null) {
    return 'unknown error';
  }

  if (typeof error === 'string' || typeof error === 'number' || typeof error === 'boolean') {
    return `${error}`;
  }

  if (error instanceof Error) {
    if (error.message.length > 0) {
      return error.message;
    }
    if (error.name.length > 0) {
      return error.name;
    }
  }

  const record = asErrorRecord(error);
  const code = record?.code;
  const message = record?.message;
  const name = record?.name;
  const stack = record?.stack;

  if ((typeof code === 'string' || typeof code === 'number') && typeof message === 'string' && message.length > 0) {
    return `${code}: ${message}`;
  }

  if (typeof message === 'string' && message.length > 0) {
    return message;
  }

  try {
    const serialized = JSON.stringify(error);
    if (serialized.length > 0 && serialized !== '{}') {
      return serialized;
    }
  } catch (_error) {}

  if (typeof name === 'string' && name.length > 0) {
    return name;
  }

  if (typeof stack === 'string' && stack.length > 0) {
    return stack;
  }

  return 'unknown error';
}

export function shouldUseMemoryStore(error: ErrorValue): boolean {
  const code = getErrorCode(error);
  if (code === 401 || code === 801 || code === 100001 || code === 15500000 || code === 15501001) {
    return true;
  }

  const message = formatError(error).toLowerCase();
  return message.includes('preview')
    || message.includes('capability not supported')
    || message.includes('stage mode only')
    || message.includes('context is unavailable')
    || message.includes('context is invalid');
}
