// https://knoedlinger.pages.dev/api/board/<ticket|entry|list>: die Ehrentafel, the global highscore board.
import { handleBoard } from '../../../board/board.js';

export const onRequest = ({ request, env, params }) => handleBoard(request, env, params.action);
