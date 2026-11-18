package CodeTrack;

import org.springframework.boot.SpringApplication;
import org.springframework.boot.autoconfigure.SpringBootApplication;
import org.springframework.scheduling.annotation.EnableScheduling;

@SpringBootApplication
@EnableScheduling
public class CodetrackApplication {
    public static void main(String[] args) {
        SpringApplication.run(CodetrackApplication.class, args);
    }
}
