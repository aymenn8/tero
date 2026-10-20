// Fixed inline inputs only: no remote URL fetching, uploaded-file persistence or tools.
export function validSummaryFile(file) {
  if (!file || typeof file !== 'object' || Array.isArray(file)
      || Object.keys(file).some(key => !['mime', 'data'].includes(key))
      || !['image/jpeg', 'application/pdf'].includes(file.mime)
      || typeof file.data !== 'string' || !file.data.length || file.data.length > 5_333_336
      || file.data.length % 4 || !/^[A-Za-z0-9+/]+={0,2}$/.test(file.data)) return false;
  try {
    const bytes = atob(file.data);
    if (bytes.length > 4_000_000) return false;
    return file.mime === 'application/pdf' ? bytes.startsWith('%PDF-') : bytes.startsWith('\xff\xd8\xff');
  } catch { return false; }
}
export function summaryContent(file) {
  const data = `data:${file.mime};base64,${file.data}`;
  return [{ type: 'input_text', text: 'Summarize and explain the attached file.' },
    file.mime === 'application/pdf'
      ? {type: 'input_file', filename: 'document.pdf', file_data: data}
      : {type: 'input_image', image_url: data, detail: 'auto'}];
}
