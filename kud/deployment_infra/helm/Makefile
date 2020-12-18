PACKAGE_DIR := charts

HELM_CHARTS := multus nfd sriov

.PHONY: $(HELM_CHARTS)

all: $(HELM_CHARTS)

$(HELM_CHARTS):
	@echo "\n[$@]"
	@make package-$@

dep-%:
	@helm dep up $*

lint-%: dep-%
	@if [ -f $*/Chart.yaml ]; then helm lint $*; fi

package-%: lint-%
	@mkdir -p $(PACKAGE_DIR)
	@if [ -f $*/Chart.yaml ]; then helm package -d $(PACKAGE_DIR) $*; fi
	@helm repo index $(PACKAGE_DIR)
