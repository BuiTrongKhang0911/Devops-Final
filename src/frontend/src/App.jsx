import { useState, useEffect, useRef } from 'react';
import { documentApi } from './api/documentApi';
import mammoth from 'mammoth';

const formatDate = (dateString) => {
  const date = new Date(dateString);
  const day = String(date.getDate()).padStart(2, '0');
  const month = String(date.getMonth() + 1).padStart(2, '0');
  const year = date.getFullYear();
  const hours = String(date.getHours()).padStart(2, '0');
  const minutes = String(date.getMinutes()).padStart(2, '0');
  return `${day}/${month}/${year} ${hours}:${minutes}`;
};

// Lấy icon theo extension
const getFileIcon = (fileName) => {
  const ext = fileName.split('.').pop()?.toLowerCase();
  const colorMap = {
    pdf: { bg: 'bg-red-100', text: 'text-red-600', label: 'PDF' },
    doc: { bg: 'bg-blue-100', text: 'text-blue-600', label: 'DOC' },
    docx: { bg: 'bg-blue-100', text: 'text-blue-600', label: 'DOCX' },
    xls: { bg: 'bg-green-100', text: 'text-green-600', label: 'XLS' },
    xlsx: { bg: 'bg-green-100', text: 'text-green-600', label: 'XLSX' },
    ppt: { bg: 'bg-orange-100', text: 'text-orange-600', label: 'PPT' },
    pptx: { bg: 'bg-orange-100', text: 'text-orange-600', label: 'PPTX' },
    txt: { bg: 'bg-gray-100', text: 'text-gray-600', label: 'TXT' },
    jpg: { bg: 'bg-pink-100', text: 'text-pink-600', label: 'JPG' },
    jpeg: { bg: 'bg-pink-100', text: 'text-pink-600', label: 'JPEG' },
    png: { bg: 'bg-purple-100', text: 'text-purple-600', label: 'PNG' },
    gif: { bg: 'bg-indigo-100', text: 'text-indigo-600', label: 'GIF' },
    zip: { bg: 'bg-yellow-100', text: 'text-yellow-600', label: 'ZIP' },
    rar: { bg: 'bg-yellow-100', text: 'text-yellow-600', label: 'RAR' },
  };
  return colorMap[ext] || { bg: 'bg-gray-100', text: 'text-gray-600', label: ext?.toUpperCase() || 'FILE' };
};

// Previewable extensions (dùng blob URL)
const PREVIEWABLE = ['pdf', 'jpg', 'jpeg', 'png', 'gif', 'txt'];
// Preview bằng mammoth (đọc text/HTML từ file)
const MAMMOTH_PREVIEWABLE = ['docx'];

function App() {
  const [documents, setDocuments] = useState([]);
  const [loading, setLoading] = useState(false);
  const [message, setMessage] = useState({ text: '', type: '' });

  // Upload form state
  const [uploadName, setUploadName] = useState('');
  const [uploadFile, setUploadFile] = useState(null);

  // Edit modal state
  const [editDoc, setEditDoc] = useState(null);
  const [editName, setEditName] = useState('');
  const [editFile, setEditFile] = useState(null);

  // Preview modal state
  const [previewDoc, setPreviewDoc] = useState(null);
  const [previewUrl, setPreviewUrl] = useState(null);
  const [previewLoading, setPreviewLoading] = useState(false);
  const [previewHtml, setPreviewHtml] = useState(null); // nội dung mammoth cho docx

  // Ref để reset input file (React way — không dùng document.getElementById)
  const uploadFileRef = useRef(null);

  // Load documents
  const loadDocuments = async () => {
    try {
      const data = await documentApi.getAll();
      setDocuments(data);
    } catch (error) {
      showMessage('Không thể tải danh sách tài liệu', 'error');
    }
  };

  useEffect(() => {
    loadDocuments();
  }, []);

  // Cleanup preview URL when unmounting or closing
  useEffect(() => {
    return () => {
      if (previewUrl) URL.revokeObjectURL(previewUrl);
    };
  }, [previewUrl]);

  // Show message
  const showMessage = (text, type) => {
    setMessage({ text, type });
    setTimeout(() => setMessage({ text: '', type: '' }), 3000);
  };

  // Upload handle
  const handleUpload = async (e) => {
    e.preventDefault();
    if (!uploadName.trim() || !uploadFile) {
      showMessage('Vui lòng nhập tên và chọn file', 'error');
      return;
    }

    setLoading(true);
    try {
      await documentApi.upload(uploadName.trim(), uploadFile);
      showMessage('Upload thành công!', 'success');
      setUploadName('');
      setUploadFile(null);
      // Reset file input bằng ref (React way)
      if (uploadFileRef.current) uploadFileRef.current.value = '';
      loadDocuments();
    } catch (error) {
      showMessage('Upload thất bại', 'error');
    } finally {
      setLoading(false);
    }
  };

  // Download handle
  const handleDownload = async (doc) => {
    try {
      await documentApi.download(doc.id, doc.fileName);
      showMessage('Đang tải xuống...', 'success');
    } catch (error) {
      showMessage('Tải xuống thất bại', 'error');
    }
  };

  // Open preview modal
  const openPreview = async (doc) => {
    const ext = doc.fileName.split('.').pop()?.toLowerCase();
    const canPreview = PREVIEWABLE.includes(ext);
    const canMammoth = MAMMOTH_PREVIEWABLE.includes(ext);

    setPreviewDoc({ ...doc, canPreview, canMammoth });
    setPreviewLoading(true);
    setPreviewUrl(null);
    setPreviewHtml(null);

    // File dùng blob URL (PDF, ảnh, txt)
    if (canPreview) {
      try {
        const response = await fetch(`/api/documents/${doc.id}`);
        if (!response.ok) throw new Error();
        const blob = await response.blob();
        const url = URL.createObjectURL(blob);
        setPreviewUrl(url);
      } catch {
        showMessage('Không thể xem trước file', 'error');
        setPreviewDoc(null);
      }
    }

    // File dùng mammoth (docx)
    if (canMammoth) {
      try {
        const response = await fetch(`/api/documents/${doc.id}`);
        if (!response.ok) throw new Error();
        const blob = await response.blob();
        const arrayBuffer = await blob.arrayBuffer();
        const result = await mammoth.convertToHtml({ arrayBuffer });
        setPreviewHtml(result.value); // HTML string từ nội dung docx
      } catch {
        showMessage('Không thể xem trước file', 'error');
        setPreviewDoc(null);
      }
    }

    setPreviewLoading(false);
  };

  // Close preview modal
  const closePreview = () => {
    if (previewUrl) URL.revokeObjectURL(previewUrl);
    setPreviewUrl(null);
    setPreviewHtml(null);
    setPreviewDoc(null);
  };

  // Open edit modal
  const openEditModal = (doc) => {
    setEditDoc(doc);
    setEditName(doc.name);
    setEditFile(null);
  };

  // Save edit
  const handleSaveEdit = async () => {
    if (!editName.trim()) {
      showMessage('Tên không được để trống', 'error');
      return;
    }

    setLoading(true);
    try {
      await documentApi.update(editDoc.id, editName.trim(), editFile);
      showMessage('Cập nhật thành công!', 'success');
      setEditDoc(null);
      loadDocuments();
    } catch (error) {
      showMessage('Cập nhật thất bại', 'error');
    } finally {
      setLoading(false);
    }
  };

  // Delete handle
  const handleDelete = async (id) => {
    if (!window.confirm('Bạn có chắc muốn xóa tài liệu này?')) return;

    setLoading(true);
    try {
      await documentApi.delete(id);
      showMessage('Xóa thành công!', 'success');
      loadDocuments();
    } catch (error) {
      showMessage('Xóa thất bại', 'error');
    } finally {
      setLoading(false);
    }
  };

  return (
    <div className="min-h-screen bg-gray-50 py-10 px-4">
      <div className="max-w-5xl mx-auto">

        {/* Header */}
        <div className="text-center mb-10">
          <h1 className="text-4xl font-bold text-gray-800 mb-2">
            Hệ Thống Quản Lý Tài Liệu
          </h1>
          <p className="text-gray-500">Document Management System v1.0.3</p>
        </div>

        {/* Toast Message */}
        {message.text && (
          <div className={`mb-6 px-4 py-3 rounded-lg text-sm font-medium transition-all ${
            message.type === 'success'
              ? 'bg-green-100 text-green-800 border border-green-200'
              : 'bg-red-100 text-red-800 border border-red-200'
          }`}>
            {message.text}
          </div>
        )}

        {/* Upload Form */}
        <div className="bg-white rounded-xl shadow-sm border border-gray-200 p-6 mb-8">
          <h2 className="text-xl font-semibold text-gray-700 mb-4 flex items-center gap-2">
            <svg className="w-5 h-5 text-blue-500" fill="none" stroke="currentColor" viewBox="0 0 24 24">
              <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2}
                d="M4 16v1a3 3 0 003 3h10a3 3 0 003-3v-1m-4-8l-4-4m0 0L8 8m4-4v12" />
            </svg>
            Upload Tài Liệu Mới
          </h2>
          <form onSubmit={handleUpload} className="flex flex-col sm:flex-row gap-4 items-start sm:items-end">
            <div className="flex-1 w-full">
              <label className="block text-sm font-medium text-gray-700 mb-1">
                Tên tài liệu
              </label>
              <input
                type="text"
                value={uploadName}
                onChange={(e) => setUploadName(e.target.value)}
                placeholder="Nhập tên tài liệu..."
                className="w-full px-4 py-2 border border-gray-300 rounded-lg focus:ring-2 focus:ring-blue-500 focus:border-blue-500 outline-none transition"
              />
            </div>
            <div className="flex-1 w-full">
              <label className="block text-sm font-medium text-gray-700 mb-1">
                Chọn file
              </label>
              <input
                ref={uploadFileRef}
                type="file"
                onChange={(e) => setUploadFile(e.target.files[0])}
                className="w-full text-sm text-gray-600 file:mr-4 file:py-2 file:px-4 file:rounded-lg file:border-0 file:text-sm file:font-semibold file:bg-blue-50 file:text-blue-700 hover:file:bg-blue-100 cursor-pointer"
              />
            </div>
            <button
              type="submit"
              disabled={loading}
              className="px-6 py-2 bg-blue-600 text-white rounded-lg font-medium hover:bg-blue-700 disabled:opacity-50 disabled:cursor-not-allowed transition whitespace-nowrap"
            >
              {loading ? 'Đang upload...' : 'Upload'}
            </button>
          </form>
        </div>

        {/* Documents Table */}
        <div className="bg-white rounded-xl shadow-sm border border-gray-200 overflow-hidden">
          <div className="px-6 py-4 border-b border-gray-200">
            <h2 className="text-xl font-semibold text-gray-700">
              Danh Sách Tài Liệu ({documents.length})
            </h2>
          </div>

          {documents.length === 0 ? (
            <div className="text-center py-16 text-gray-400">
              <svg className="w-16 h-16 mx-auto mb-4 opacity-30" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={1.5}
                  d="M9 12h6m-6 4h6m2 5H7a2 2 0 01-2-2V5a2 2 0 012-2h5.586a1 1 0 01.707.293l5.414 5.414a1 1 0 01.293.707V19a2 2 0 01-2 2z" />
              </svg>
              <p>Chưa có tài liệu nào</p>
              <p className="text-sm mt-1">Upload tài liệu đầu tiên của bạn</p>
            </div>
          ) : (
            <div className="overflow-x-auto">
              <table className="w-full">
                <thead className="bg-gray-50">
                  <tr>
                    <th className="px-6 py-3 text-left text-xs font-semibold text-gray-500 uppercase tracking-wider">#</th>
                    <th className="px-6 py-3 text-left text-xs font-semibold text-gray-500 uppercase tracking-wider">Tên tài liệu</th>
                    <th className="px-6 py-3 text-left text-xs font-semibold text-gray-500 uppercase tracking-wider">File gốc</th>
                    <th className="px-6 py-3 text-left text-xs font-semibold text-gray-500 uppercase tracking-wider">Ngày upload</th>
                    <th className="px-6 py-3 text-center text-xs font-semibold text-gray-500 uppercase tracking-wider">Thao tác</th>
                  </tr>
                </thead>
                <tbody className="divide-y divide-gray-100">
                  {documents.map((doc, index) => {
                    const icon = getFileIcon(doc.fileName);
                    return (
                      <tr key={doc.id} className="hover:bg-gray-50 transition cursor-pointer"
                        onClick={() => openPreview(doc)}>
                        <td className="px-6 py-4 text-sm text-gray-500 font-medium">{index + 1}</td>
                        <td className="px-6 py-4">
                          <div className="flex items-center gap-3">
                            <div className={`w-10 h-10 rounded-lg ${icon.bg} flex items-center justify-center flex-shrink-0`}>
                              <span className={`text-xs font-bold ${icon.text}`}>{icon.label}</span>
                            </div>
                            <span className="text-sm font-medium text-gray-800 truncate max-w-[200px]">{doc.name}</span>
                          </div>
                        </td>
                        <td className="px-6 py-4 text-sm text-gray-500 truncate max-w-[150px]">{doc.fileName}</td>
                        <td className="px-6 py-4 text-sm text-gray-500">{formatDate(doc.uploadTime)}</td>
                        <td className="px-6 py-4 text-center" onClick={(e) => e.stopPropagation()}>
                          <div className="flex items-center justify-center gap-2">
                            {/* Download */}
                            <button
                              onClick={() => handleDownload(doc)}
                              className="p-2 text-blue-600 hover:bg-blue-50 rounded-lg transition"
                              title="Tải xuống"
                            >
                              <svg className="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                                <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2}
                                  d="M4 16v1a3 3 0 003 3h10a3 3 0 003-3v-1m-4-4l-4 4m0 0l-4-4m4 4V4" />
                              </svg>
                            </button>
                            {/* Edit */}
                            <button
                              onClick={() => openEditModal(doc)}
                              className="p-2 text-yellow-600 hover:bg-yellow-50 rounded-lg transition"
                              title="Sửa"
                            >
                              <svg className="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                                <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2}
                                  d="M11 5H6a2 2 0 00-2 2v11a2 2 0 002 2h11a2 2 0 002-2v-5m-1.414-9.414a2 2 0 112.828 2.828L11.828 15H9v-2.828l8.586-8.586z" />
                              </svg>
                            </button>
                            {/* Delete */}
                            <button
                              onClick={() => handleDelete(doc.id)}
                              disabled={loading}
                              className="p-2 text-red-600 hover:bg-red-50 rounded-lg transition disabled:opacity-50"
                              title="Xóa"
                            >
                              <svg className="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                                <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2}
                                  d="M19 7l-.867 12.142A2 2 0 0116.138 21H7.862a2 2 0 01-1.995-1.858L5 7m5 4v6m4-6v6m1-10V4a1 1 0 00-1-1h-4a1 1 0 00-1 1v3M4 7h16" />
                              </svg>
                            </button>
                          </div>
                        </td>
                      </tr>
                    );
                  })}
                </tbody>
              </table>
            </div>
          )}
        </div>
      </div>

      {/* Preview Modal */}
      {previewDoc && (
        <div
          className="fixed inset-0 bg-black/60 flex items-center justify-center z-50 p-4"
          onClick={closePreview}
        >
          <div
            className="bg-white rounded-2xl shadow-2xl w-full max-w-4xl max-h-[90vh] flex flex-col overflow-hidden"
            onClick={(e) => e.stopPropagation()}
          >
            {/* Preview Header */}
            <div className="flex items-center justify-between px-6 py-4 border-b border-gray-200">
              <div className="flex items-center gap-3 min-w-0">
                {(() => {
                  const icon = getFileIcon(previewDoc.fileName);
                  return (
                    <div className={`w-10 h-10 rounded-lg ${icon.bg} flex items-center justify-center flex-shrink-0`}>
                      <span className={`text-xs font-bold ${icon.text}`}>{icon.label}</span>
                    </div>
                  );
                })()}
                <div className="min-w-0">
                  <h3 className="font-semibold text-gray-800 truncate">{previewDoc.name}</h3>
                  <p className="text-sm text-gray-400 truncate">{previewDoc.fileName}</p>
                </div>
              </div>
              <div className="flex items-center gap-2 ml-4 flex-shrink-0">
                <button
                  onClick={() => handleDownload(previewDoc)}
                  className="px-4 py-2 bg-blue-600 text-white text-sm rounded-lg font-medium hover:bg-blue-700 transition"
                >
                  Tải xuống
                </button>
                <button
                  onClick={closePreview}
                  className="p-2 text-gray-400 hover:text-gray-600 hover:bg-gray-100 rounded-lg transition"
                >
                  <svg className="w-5 h-5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                    <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M6 18L18 6M6 6l12 12" />
                  </svg>
                </button>
              </div>
            </div>

            {/* Preview Content */}
            <div className="flex-1 overflow-auto bg-gray-100 flex items-center justify-center min-h-[400px]">
              {previewLoading ? (
                <div className="text-gray-400 flex flex-col items-center gap-3">
                  <div className="w-8 h-8 border-3 border-blue-600 border-t-transparent rounded-full animate-spin" />
                  <span>Đang tải...</span>
                </div>
              ) : previewUrl && previewDoc.canPreview ? (
                (() => {
                  const ext = previewDoc.fileName.split('.').pop()?.toLowerCase();
                  if (['jpg', 'jpeg', 'png', 'gif'].includes(ext)) {
                    return (
                      <img
                        src={previewUrl}
                        alt={previewDoc.name}
                        className="max-w-full max-h-[70vh] object-contain rounded-lg shadow-lg"
                      />
                    );
                  }
                  if (ext === 'pdf') {
                    return (
                      <iframe
                        src={previewUrl}
                        title={previewDoc.name}
                        className="w-full h-[70vh] rounded-lg"
                      />
                    );
                  }
                  if (ext === 'txt') {
                    return (
                      <iframe
                        src={previewUrl}
                        title={previewDoc.name}
                        className="w-full h-[70vh] rounded-lg bg-white"
                      />
                    );
                  }
                  return null;
                })()
              ) : previewHtml && previewDoc.canMammoth ? (
                /* DOCX — hiển thị nội dung HTML từ mammoth (giống mở Word) */
                <div
                  className="w-full h-[70vh] overflow-auto bg-white rounded-lg shadow-lg p-8 prose max-w-none"
                  dangerouslySetInnerHTML={{ __html: previewHtml }}
                />
              ) : (
                <div className="text-center text-gray-400">
                  <svg className="w-20 h-20 mx-auto mb-4 opacity-30" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                    <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={1}
                      d="M9 12h6m-6 4h6m2 5H7a2 2 0 01-2-2V5a2 2 0 012-2h5.586a1 1 0 01.707.293l5.414 5.414a1 1 0 01.293.707V19a2 2 0 01-2 2z" />
                  </svg>
                  <p className="font-medium">Không thể xem trước định dạng này</p>
                  <p className="text-sm mt-1">Tải xuống để mở file</p>
                  <button
                    onClick={() => handleDownload(previewDoc)}
                    className="mt-4 px-6 py-2 bg-blue-600 text-white rounded-lg text-sm font-medium hover:bg-blue-700 transition"
                  >
                    Tải xuống
                  </button>
                </div>
              )}
            </div>
          </div>
        </div>
      )}

      {/* Edit Modal */}
      {editDoc && (
        <div
          className="fixed inset-0 bg-black/40 flex items-center justify-center z-50"
          onClick={() => setEditDoc(null)}
        >
          <div
            className="bg-white rounded-xl shadow-xl w-full max-w-md mx-4 p-6"
            onClick={(e) => e.stopPropagation()}
          >
            <h3 className="text-lg font-semibold text-gray-800 mb-4">Cập Nhật Tài Liệu</h3>
            <div className="space-y-4">
              <div>
                <label className="block text-sm font-medium text-gray-700 mb-1">Tên tài liệu</label>
                <input
                  type="text"
                  value={editName}
                  onChange={(e) => setEditName(e.target.value)}
                  className="w-full px-4 py-2 border border-gray-300 rounded-lg focus:ring-2 focus:ring-blue-500 outline-none"
                />
              </div>
              <div>
                <label className="block text-sm font-medium text-gray-700 mb-1">
                  Thay file mới (để trống nếu giữ nguyên)
                </label>
                <input
                  type="file"
                  onChange={(e) => setEditFile(e.target.files[0])}
                  className="w-full text-sm text-gray-600 file:mr-4 file:py-2 file:px-4 file:rounded-lg file:border-0 file:text-sm file:font-semibold file:bg-blue-50 file:text-blue-700 hover:file:bg-blue-100 cursor-pointer"
                />
              </div>
            </div>
            <div className="flex gap-3 mt-6">
              <button
                onClick={handleSaveEdit}
                disabled={loading}
                className="flex-1 py-2 bg-blue-600 text-white rounded-lg font-medium hover:bg-blue-700 disabled:opacity-50 transition"
              >
                Lưu
              </button>
              <button
                onClick={() => setEditDoc(null)}
                className="flex-1 py-2 bg-gray-100 text-gray-700 rounded-lg font-medium hover:bg-gray-200 transition"
              >
                Hủy
              </button>
            </div>
          </div>
        </div>
      )}
    </div>
  );
}

export default App;
