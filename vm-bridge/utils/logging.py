import os
import logging

def configure_logger(log_file, verbose=False, logger_name="vm-bridge"):
    """
    Konfiguruje logger: tworzy katalog logów, ustawia poziom, loguje do pliku i na stdout jeśli verbose.
    """
    log_dir = os.path.dirname(log_file)
    os.makedirs(log_dir, exist_ok=True)
    
    level = logging.DEBUG if verbose else logging.INFO
    logger = logging.getLogger(logger_name)
    logger.setLevel(level)

    formatter = logging.Formatter('%(asctime)s - %(name)s - %(levelname)s - %(message)s')

    # File handler
    fh = logging.FileHandler(log_file)
    fh.setLevel(level)
    fh.setFormatter(formatter)
    logger.addHandler(fh)

    # Stream handler (console)
    if verbose:
        sh = logging.StreamHandler()
        sh.setLevel(level)
        sh.setFormatter(formatter)
        logger.addHandler(sh)

    logger.info("System logowania skonfigurowany")
    return logger
