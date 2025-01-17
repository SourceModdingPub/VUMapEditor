<template>
	<EditorComponent class="grid-component" :title="title">
		<div class="header">
			<Search v-model="data.search" @search="onSearch" />
			<input type="range" min="5" max="10" step="1" v-model="data.scale" />
		</div>
		<div class="container scrollable" ref="scroller">
			<div class="grid-container" v-if="data.scale > 5">
				<div
					class="grid-item"
					v-tooltip="item.fileName"
					v-for="(item, index) in filteredItems()"
					:key="index"
					@click="onClick(item)"
					@mousedown="onMouseDown($event, item)"
				>
					<slot name="grid" :item="item" :data="data"></slot>
				</div>
			</div>
			<div class="list-container" v-else>
				<DynamicScroller :items="filteredItems()" class="" :min-item-size="22" :key-field="keyField">
					<DynamicScrollerItem
						class="tr"
						slot-scope="{ item, active }"
						:item="item"
						:active="active"
						:size-dependencies="[item.expanded]"
						:min-item-size="22"
						@click.native="onClick(item)"
						@mousedown.native="onMouseDown($event, item)"
						:key-field="keyField"
					>
						<slot name="list" :item="item" :data="data"> </slot>
					</DynamicScrollerItem>
				</DynamicScroller>
			</div>
		</div>
		<div v-html="style"></div>
	</EditorComponent>
</template>

<script lang="ts">
import { Component, Prop } from 'vue-property-decorator';
import EditorComponent from './EditorComponent.vue';
import { DynamicScroller, DynamicScrollerItem, RecycleScroller } from 'vue-virtual-scroller';
import 'vue-virtual-scroller/dist/vue-virtual-scroller.css';
import Search from '@/script/components/widgets/Search.vue';
import { Blueprint } from '@/script/types/Blueprint';
import Highlighter from '@/script/components/widgets/Highlighter.vue';

@Component({
	components: { Highlighter, RecycleScroller, DynamicScroller, DynamicScrollerItem, Search, EditorComponent }
})
export default class GridComponent extends EditorComponent {
	@Prop(Array) list: { name: string }[];
	@Prop(String) keyField: string;
	@Prop(Array) headers: string[];
	@Prop(Function) click: void;
	@Prop(Boolean) rightAlign: boolean;

	data: {
		search: string;
		scale: number;
	} = {
		search: '',
		scale: 6
	};

	get style() {
		let icon = 40;
		let grid = 12;
		switch (this.data.scale.toString()) {
			case '6':
				icon = 40;
				grid = 12;
				break;
			case '7':
				icon = 60;
				grid = 10;
				break;
			case '8':
				icon = 80;
				grid = 8;
				break;
			case '9':
				icon = 100;
				grid = 6;
				break;
			case '10':
				icon = 120;
				grid = 4;
				break;
		}
		// @ts-ignore;
		return (
			' <style> .grid-container { 	grid-template-columns: repeat(' +
			grid +
			', minmax(0, 1fr)) } .grid-item .Icon { width: ' +
			icon +
			'px; height: ' +
			icon +
			'px; } </style> '
		);
	}

	get iconStyle() {
		return {};
	}

	onMouseDown(e: any, item: Blueprint) {
		console.log(item);
		window.editor.threeManager.onDragStart(e, item);
	}

	onClick(item: any) {
		if (this.click !== undefined) {
			// @ts-ignore
			this.click(item);
		}
	}

	onSearch(a: any) {
		this.data.search = a.target.value;
	}

	filteredItems() {
		const lowerCaseSearch = this.data.search.toLowerCase();
		if (this.list === undefined) {
			return [];
		}
		if (this.$refs.scroller !== undefined) {
			(this.$refs.scroller as any).scrollTop = 0;
		}
		return this.list.filter((i) => i.name.toLowerCase().includes(lowerCaseSearch));
	}
}
</script>
<style scoped lang="scss">
.list-component {
	user-select: none;

	.header {
		font-weight: bold;
		display: flex;
		padding: 0.2vmin;
		border-bottom: solid 1px #4a4a4a;
	}
	.scrollable {
		height: 100%;
		width: 100%;
	}

	.tr {
		cursor: move;
	}
	.name {
		text-align: center;
	}
}

.container {
	position: relative;
}

.rightAlign {
	text-align: right;
}
</style>
