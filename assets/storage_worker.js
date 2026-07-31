/**
 * @typedef {object} Message
 * @prop {number} id
 * @prop {string[]} path
 * @prop {string} content */

/** @param {FileSystemDirectoryHandle} entry @param {string[]} path */
const resolvePath = async (entry, path) => {
  if (path.length === 0) return null;
  const [next, ...restPath] = path;
  for await (const child of entry.values()) {
    if (child.name !== next) continue;
    if (child instanceof FileSystemDirectoryHandle)
      return resolvePath(child, restPath);
    if (child instanceof FileSystemFileHandle && restPath.length === 0)
      return child;
  }
  return null;
};

self.addEventListener(
  "message",
  /** @param {MessageEvent<Message>} event */
  async (event) => {
    const { id, path, content } = event.data;
    try {
      const rootDir = await navigator.storage.getDirectory();
      const file = await resolvePath(rootDir, path);
      if (file == null)
        throw new Error(`File at path /${path.join("/")} could not be found`);

      const encoder = new TextEncoder();
      const content_buf = encoder.encode(content);

      const syncHandle = await file.createSyncAccessHandle();
      syncHandle.truncate(0);
      syncHandle.write(content_buf);
      syncHandle.flush();
      syncHandle.close();

      self.postMessage({ id });
    } catch (error) {
      self.postMessage({ id, error });
    }
  },
);
