import java.io.BufferedReader;
import java.io.IOException;
import java.io.InputStreamReader;
import java.io.OutputStream;
import java.net.HttpURLConnection;
import java.net.InetSocketAddress;
import java.net.URL;

import com.sun.net.httpserver.HttpExchange;
import com.sun.net.httpserver.HttpHandler;
import com.sun.net.httpserver.HttpServer;

import org.apache.logging.log4j.LogManager;
import org.apache.logging.log4j.Logger;

public class Main {
    private static final Logger logger = LogManager.getLogger(Main.class);

    public static void main(String[] args) throws IOException, InterruptedException {
        String html = "{'services':[{'name':'Visa Processor','status':'online'},{'name':'Mastercard Processor','status':'online'}]}";
        String listenPort = System.getProperty("listen");
        String connectList = System.getProperty("connect");

        if (listenPort != null && !listenPort.isEmpty()) {
            HttpServer server = HttpServer.create(new InetSocketAddress(Integer.parseInt(listenPort)), 0);
            server.createContext("/", new MyHandler(html));
            server.createContext("/ping", new MyHandler("pong"));
            server.createContext("/posts", new MyHandler(exploitEnabledResponse(), exploitDisabledResponse()));
            server.start();
            logger.info("Server started on port: " + listenPort);
        }

        if (connectList != null && !connectList.isEmpty()) {
            for (;;) {
                String[] hosts = connectList.split(",");
                for (String host : hosts) {
                    String[] hostParts = host.split(":");
                    String hostname = hostParts[0];
                    int port = Integer.parseInt(hostParts[1]);

                    try {
                        URL url = new URL("http://" + hostname + ":" + port);
                        HttpURLConnection connection = (HttpURLConnection) url.openConnection();
                        connection.setRequestMethod("GET");
                        int responseCode = connection.getResponseCode();
                        logger.info("Response from " + hostname + ":" + port + ": " + responseCode);

                        if (responseCode == HttpURLConnection.HTTP_OK) {
                            BufferedReader reader = new BufferedReader(new InputStreamReader(connection.getInputStream()));
                            StringBuilder response = new StringBuilder();
                            String line;

                            while ((line = reader.readLine()) != null) {
                                response.append(line);
                            }

                            reader.close();
                            String htmlContent = response.toString();

                            if (!htmlContent.isEmpty()) {
                                logger.info("Received valid response from " + hostname);
                            }
                        }

                        connection.disconnect();
                    } catch (IOException e) {
                        logger.error("Connection to " + hostname + ":" + port + " failed: " + e.getMessage(), e);
                    }
                }
                try {
                    Thread.sleep(1000);
                } catch (InterruptedException e) {
                    logger.error("Thread interrupted: " + e.getMessage(), e);
                }
            }
        }

    }

    private static void logRequest(HttpExchange exchange, String method) {
        logger.info("Received " + method + " request: " + exchange.getRequestURI());
    }

    private static String exploitEnabledResponse() {
        return "RCE is enabled\n";
    }

    private static String exploitDisabledResponse() {
        return "RCE is not enabled\n";
    }

    static class MyHandler implements HttpHandler {
        private final String response;

        public MyHandler(String response) {
            this.response = response;
        }

        public MyHandler(String exploitEnabledResponse, String exploitDisabledResponse) {
            String exploit = System.getenv("exploit");
            this.response = (exploit != null && exploit.equals("true")) ? exploitEnabledResponse : exploitDisabledResponse;
        }

        @Override
        public void handle(HttpExchange exchange) throws IOException {
            logRequest(exchange, exchange.getRequestMethod());
            byte[] responseBytes = response.getBytes();
            exchange.sendResponseHeaders(200, responseBytes.length);
            try (OutputStream os = exchange.getResponseBody()) {
                os.write(responseBytes);
            }
        }
    }
}

