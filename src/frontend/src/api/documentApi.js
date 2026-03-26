import axios from 'axios';

// Sử dụng relative URL — dev mode dùng Vite proxy, production dùng Nginx proxy
const API_BASE = '/api/documents';

export const documentApi = {
  // Upload document
  upload: async (name, file) => {
    const formData = new FormData();
    formData.append('name', name);
    formData.append('file', file);
    const response = await axios.post(API_BASE, formData, {
      headers: { 'Content-Type': 'multipart/form-data' },
    });
    return response.data;
  },

  // Get all documents
  getAll: async () => {
    const response = await axios.get(API_BASE);
    return response.data;
  },

  // Download document
  download: async (id, fileName) => {
    const response = await axios.get(`${API_BASE}/${id}`, {
      responseType: 'blob',
    });
    const url = window.URL.createObjectURL(new Blob([response.data]));
    const link = document.createElement('a');
    link.href = url;
    link.setAttribute('download', fileName);
    document.body.appendChild(link);
    link.click();
    link.remove();
    window.URL.revokeObjectURL(url);
  },

  // Update document
  update: async (id, name, file) => {
    const formData = new FormData();
    if (name) formData.append('name', name);
    if (file) formData.append('file', file);
    const response = await axios.put(`${API_BASE}/${id}`, formData, {
      headers: { 'Content-Type': 'multipart/form-data' },
    });
    return response.data;
  },

  // Delete document
  delete: async (id) => {
    await axios.delete(`${API_BASE}/${id}`);
  },
};
