import { Result$Ok, Result$Error } from "../../prelude.mjs";
import { to_list as array_to_list } from "../../gleam_javascript/gleam/javascript/array.mjs";
import {
  new_could_not_get_storage_manager,
  new_could_not_persist,
  new_could_not_get_root_directory,
  new_file_system_error,
} from "./storage.mjs";

/** @param {(any) => any} ErrorConstructor @param {(...args) => Promise} fn */
const catchErrors =
  (fn, ErrorConstructor = new_file_system_error) =>
  (...args) =>
    fn(...args).catch((error) => {
      const message = error?.toString?.();
      if (message == undefined)
        console.warn("Could not get message for error:", error);
      return Result$Error(ErrorConstructor(message ?? "Unknown error"));
    });

export const persist = catchErrors(async () => {
  if (!navigator.storage)
    return Result$Error(new_could_not_get_storage_manager());
  return Result$Ok(await navigator.storage.persist());
}, new_could_not_persist);

export const get_root_directory = catchErrors(async () => {
  if (!navigator.storage)
    return Result$Error(new_could_not_get_storage_manager());

  const rootDir = await navigator.storage.getDirectory();
  return Result$Ok(rootDir);
}, new_could_not_get_root_directory);

export const all_entries = catchErrors(
  /** @param {FileSystemDirectoryHandle} dir */ async (dir) => {
    const dirs = [];
    const files = [];
    for await (const entry of dir.values()) {
      if (entry instanceof FileSystemDirectoryHandle) dirs.push(entry);
      else if (entry instanceof FileSystemFileHandle) files.push(entry);
      else throw new Error(`Unknown file system entry type: ${typeof entry}`);
    }
    return Result$Ok([array_to_list(dirs), array_to_list(files)]);
  },
);

export const get_directory_handle = catchErrors(
  /** @param {FileSystemDirectoryHandle} dir @param {string} name @param {boolean} create */
  async (dir, name, create) =>
    Result$Ok(await dir.getDirectoryHandle(name, { create })),
);

export const get_file_handle = catchErrors(
  /** @param {FileSystemDirectoryHandle} dir @param {string} name @param {boolean} create */
  async (dir, name, create) =>
    Result$Ok(await dir.getFileHandle(name, { create })),
);

export const remove_entry = catchErrors(
  /** @param {FileSystemDirectoryHandle} dir @param {string} name @param {boolean} recursive */
  async (dir, name, recursive) =>
    Result$Ok(await dir.removeEntry(name, { recursive })),
);

export const get_file = catchErrors(
  /** @param {FileSystemFileHandle} handle */
  async (handle) => Result$Ok(await handle.getFile()),
);

export const file_text = catchErrors(
  /** @param {File} file */ async (file) => Result$Ok(await file.text()),
);

// FIXME: This is relative to the current HTML page. The fix might be hosting on
//        a subdomain so an absolute path can be used.
const storageWorker = new Worker("./storage_worker.js", { type: "module" });

/**
 * @typedef {object} Message
 * @prop {number} id
 * @prop {string[]} path
 * @prop {string} content */

/** @type {{ id: number, resolve: () => void, reject: (error: any) => void }[]} */
const listeners = [];
let nextMessageId = 0;
storageWorker.addEventListener(
  "message",
  /** @param {MessageEvent<{ id: number, error?: any }>} event */ (event) => {
    for (const listener of listeners) {
      if (listener.id === event.data.id) {
        if (event.error) {
          listener.reject(event.data.error);
        } else {
          listener.resolve();
        }
      }
    }
  },
);

export const write_file = catchErrors(
  /** @param {FileSystemFileHandle} file @param {string} contents */
  async (file, content) => {
    if (!navigator.storage)
      return Result$Error(new_could_not_get_storage_manager());
    const rootDir = await navigator.storage.getDirectory();
    const path = await rootDir.resolve(file);
    console.log(path);

    /** @type {Message} */
    const data = { id: nextMessageId++, path, content };
    storageWorker.postMessage(data);
    return new Promise((resolve, reject) => {
      listeners.push({
        id: data.id,
        resolve: () => resolve(Result$Ok(undefined)),
        reject,
      });
    });
  },
);
