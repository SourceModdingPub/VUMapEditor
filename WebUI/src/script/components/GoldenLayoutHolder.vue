<template>
	<div id="glHolder">
		<golden-layout
			:hasHeaders="true"
			:reorderEnabled="true"
			:selectionEnabled="true"
			:popoutWholeStack="true"
			:closePopoutsOnUnload="false"
			:showPopoutIcon="false"
			:showMaximiseIcon="false"
			:showCloseIcon="true"
			:headerHeight="30"
			ref="gl"
			class="gl"
			@initialised="onInitialised"
			@stackCreated="onStackCreated"
		>
			<gl-row>
				<gl-col>
					<gl-row>
						<gl-col width="18">
							<HierarchyComponent />
						</gl-col>
						<ViewportComponent :showHeader="true" :closable="false" />
					</gl-row>
					<gl-row height="25">
						<ExplorerComponent />
					</gl-row>
				</gl-col>
				<gl-col width="20">
					<gl-stack>
						<InspectorComponent />
						<HistoryComponent />
					</gl-stack>
				</gl-col>
			</gl-row>
		</golden-layout>
	</div>
</template>

<script lang="ts">
import { Component, Vue } from 'vue-property-decorator';
import ExplorerComponent from '@/script/components/EditorComponents/ExplorerComponent.vue';
import ConsoleComponent from '@/script/components/EditorComponents/ConsoleComponent.vue';
import ViewportComponent from '@/script/components/EditorComponents/ViewportComponent.vue';
import HierarchyComponent from '@/script/components/EditorComponents/HierarchyComponent.vue';
import InspectorComponent from '@/script/components/EditorComponents/Inspector/InspectorComponent.vue';
import HistoryComponent from '@/script/components/EditorComponents/HistoryComponent.vue';
import PerfectScrollbar from 'perfect-scrollbar';

@Component({
	components: {
		ExplorerComponent,
		ConsoleComponent,
		ViewportComponent,
		HierarchyComponent,
		InspectorComponent,
		HistoryComponent
	}
})
export default class GoldenLayoutHolder extends Vue {
	onInitialised() {
		const viewport = document.getElementById('viewport-component');
		if (viewport !== null && viewport.parentElement !== null && viewport.parentElement.parentElement !== null) {
			viewport.parentElement.parentElement.setAttribute('id', 'viewport-container');
		}
		this.onMount();
	}

	onStackCreated(stack: any) {
		this.$nextTick(() => {
			if (stack.contentItems.length > 0) {
				if (!stack.contentItems[0].vueObject.$vnode.context.showHeader) {
					stack.header.position();
				}
			}
		});
	}

	onMount() {
		this.$nextTick(() => {
			(this.$refs.gl as any).layout.onResize();
			const scrollables = document.getElementsByClassName('scrollable');
			for (const scrollable of scrollables as any) {
				new PerfectScrollbar(scrollable as HTMLElement, {
					minScrollbarLength: 35
				});
			}
		});
	}
}
</script>

<style>
.gl {
	height: 100%;
}
#glHolder {
	height: calc(100vh - 40px);
	width: 100vw;
	pointer-events: none;
}
</style>
