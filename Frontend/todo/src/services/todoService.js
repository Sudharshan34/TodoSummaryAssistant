import axios from 'axios';

// Backend URL: relative by default, so it works behind nginx (Docker/EC2)
// and with the dev proxy locally. Override at build time with REACT_APP_API_URL.
const API_BASE_URL = process.env.REACT_APP_API_URL || '/api/todos';

const todoService = {
  getAllTodos: () => axios.get(API_BASE_URL),
  createTodo: (todo) => axios.post(API_BASE_URL, todo),
  updateTodo: (id, todo) => axios.put(`${API_BASE_URL}/${id}`, todo),
  deleteTodo: (id) => axios.delete(`${API_BASE_URL}/${id}`),
  summarizeTodos: () => axios.post(`${API_BASE_URL}/summarize`),
};

export default todoService;