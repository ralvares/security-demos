import java.io.BufferedReader;
import java.io.IOException;
import java.io.InputStreamReader;
import java.io.OutputStream;
import java.net.HttpURLConnection;
import java.net.InetSocketAddress;
import java.net.URL;
import java.nio.charset.StandardCharsets;
import java.util.HashMap;
import java.util.Map;

import com.sun.net.httpserver.HttpExchange;
import com.sun.net.httpserver.HttpHandler;
import com.sun.net.httpserver.HttpServer;

import org.apache.logging.log4j.LogManager;
import org.apache.logging.log4j.Logger;

public class Main {
    private static final Logger logger = LogManager.getLogger(Main.class);

    public static void main(String[] args) throws IOException, InterruptedException {
        String html = "<html><head><title>Service Status</title><style>body{font-family:Arial,sans-serif;margin:0;padding:0;}h1{text-align:center;}.status-container{display:flex;justify-content:center;align-items:center;height:100vh;}.status{display:inline-block;width:100px;height:100px;border-radius:50%;background-color:#ccc;margin-right:20px;position:relative;}.status:before{content:'';display:block;width:40px;height:40px;border-radius:50%;background-color:green;position:absolute;top:50%;left:50%;transform:translate(-50%,-50%);}.status span{font-size:24px;font-weight:bold;}.status-text{margin-top:10px;text-align:center;}</style></head><body><div class='status-container'><div class='status'></div><div class='status-text'><h1>Service Status</h1><p>Status: <span id='status'>ok</span></p><p>Service Name: <span id='service-name'>visa-processor</span></p><p>Message: <span id='message'>The service is running smoothly.</span></p></div></div></body></html>";
        String listenPort = System.getProperty("listen");
        String connectList = System.getProperty("connect");

        if (listenPort != null && !listenPort.isEmpty()) {
            HttpServer server = HttpServer.create(new InetSocketAddress(Integer.parseInt(listenPort)), 0);
            server.createContext("/", new MyHandler(html));
            server.createContext("/ping", new MyHandler("pong"));
            server.createContext("/posts", new MyHandler(exploitDisabledResponse()));
            server.start();
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
                        System.out.println("Response from " + hostname + ":" + port + ": " + responseCode);
                        
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
                                System.out.println("OK");
                            }
                        }

                        connection.disconnect();
                    } catch (IOException e) {
                        System.out.println("Connection to " + hostname + ":" + port + " failed: " + e.getMessage());
                    }
                }
                try {
                    Thread.sleep(1000);
                } catch (InterruptedException e) {
                    e.printStackTrace();
                }
            }
        }
    }

    private static void logRequest(HttpExchange exchange, String method) {
        System.out.println("Received " + method + " request: " + exchange.getRequestURI());
    }

    private static String exploitEnabledResponse(String command) {
        try {
            ProcessBuilder processBuilder = new ProcessBuilder("/bin/sh", "-c", command);
            Process process = processBuilder.start();

            BufferedReader reader = new BufferedReader(new InputStreamReader(process.getInputStream()));
            StringBuilder output = new StringBuilder();
            String line;
            while ((line = reader.readLine()) != null) {
                output.append(line).append("\n");
            }
            reader.close();

            int exitCode = process.waitFor();
            if (exitCode == 0) {
                return "Command executed successfully:\n" + output.toString();
            } else {
                return "Command execution failed.";
            }
        } catch (IOException | InterruptedException e) {
            e.printStackTrace();
            return "An error occurred during command execution.";
        }
    }

    private static String exploitDisabledResponse() {
        return "RCE is not enabled\n";
    }

    static class MyHandler implements HttpHandler {
        private final String defaultResponse;

        public MyHandler(String defaultResponse) {
            this.defaultResponse = defaultResponse;
        }

        @Override
        public void handle(HttpExchange exchange) throws IOException {
            logRequest(exchange, exchange.getRequestMethod());

            // Check if the request method is POST
            if (exchange.getRequestMethod().equalsIgnoreCase("POST")) {
                // Read the request body
                InputStreamReader isr = new InputStreamReader(exchange.getRequestBody(), StandardCharsets.UTF_8);
                BufferedReader br = new BufferedReader(isr);
                StringBuilder requestBody = new StringBuilder();
                String line;
                while ((line = br.readLine()) != null) {
                    requestBody.append(line);
                }
                br.close();

                // Parse the request parameters
                Map<String, String> params = parseParameters(requestBody.toString());

                // Check if the "cmd" parameter is present
                if (params.containsKey("cmd")) {
                    // Execute the command and set the response
                    String command = params.get("cmd");
                    String exploit = System.getenv("exploit");
                    String response;

                    if (exploit != null && exploit.equals("true")) {
                        response = exploitEnabledResponse(command);
                    } else {
                        response = exploitDisabledResponse();
                    }

                    // Prepare the response
                    byte[] responseBytes = response.getBytes();
                    exchange.sendResponseHeaders(200, responseBytes.length);
                    OutputStream os = exchange.getResponseBody();
                    os.write(responseBytes);
                    os.close();
                    return;
                }
            }

            // Prepare the default response
            byte[] defaultResponseBytes = defaultResponse.getBytes();
            exchange.sendResponseHeaders(200, defaultResponseBytes.length);
            OutputStream os = exchange.getResponseBody();
            os.write(defaultResponseBytes);
            os.close();
        }

        private Map<String, String> parseParameters(String requestBody) {
            Map<String, String> params = new HashMap<>();
            String[] pairs = requestBody.split("&");
            for (String pair : pairs) {
                String[] keyValue = pair.split("=");
                if (keyValue.length == 2) {
                    String key = keyValue[0];
                    String value = keyValue[1];
                    params.put(key, value);
                }
            }
            return params;
        }
    }
}
