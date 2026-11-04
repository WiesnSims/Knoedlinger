// wss://knoedlinger.pages.dev/api/room/<code or "new">: hands the WebSocket to that room's Durable Object.
import { routeRoom } from '../../../relay/src/route.js';

export const onRequestGet = ({ request, env, params }) => routeRoom(request, env, params.code);
