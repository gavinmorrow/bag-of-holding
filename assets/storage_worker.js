/**
 * @typedef {object} Message
 * @prop {number} id
 * @prop {FileSystemFileHandle} file
 * @prop {string} content */

self.addEventListener(
  "message",
  /** @param {MessageEvent<Message>} event */
  async (event) => {
    try {
      const { id, file, content } = event.data;
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
